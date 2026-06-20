import CloudKit
import SwiftData
import SwiftUI
import UIKit

struct FamilySyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FamilySyncViewModel()
    @State private var confirmLeave = false
    @State private var deleteLocalDataOnLeave = false

    var body: some View {
        List {
            Section("Current mode") {
                LabeledContent("Mode", value: viewModel.state.syncMode.displayName)
                LabeledContent("Status", value: viewModel.state.status.displayName)
                LabeledContent("iCloud Sync", value: viewModel.availability.title)
                LabeledContent("Role", value: viewModel.state.role.displayName)
                LabeledContent("Owner", value: viewModel.state.ownerDescription)
                LabeledContent("Participant", value: viewModel.state.participantDescription)
                if let lastSyncAt = viewModel.state.lastSyncAt {
                    LabeledContent(
                        "Last sync",
                        value: lastSyncAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }

            Section("How family sync works") {
                Text("Family Sync uses an iCloud shared record between Apple Accounts. It is separate from Apple Family Sharing membership.")
                    .foregroundStyle(.secondary)
                Text("Profiles, timers, events, appointments, milestones, photos, guide state, predictions, and Food & Home data are shared with accepted caregivers.")
                    .foregroundStyle(.secondary)
                Text("Private iCloud Sync remains available for devices signed into the same Apple Account.")
                    .foregroundStyle(.secondary)
            }

            Section("Family sharing") {
                if viewModel.state.canCreateShare {
                    Button {
                        Task { await viewModel.startSharing(context: modelContext) }
                    } label: {
                        Label("Create Family Share", systemImage: "person.crop.circle.badge.plus")
                    }
                }

                if viewModel.state.canManageShare {
                    Button {
                        Task { await viewModel.manageSharing() }
                    } label: {
                        Label("Manage Caregivers", systemImage: "person.2")
                    }
                }

                if viewModel.state.canSyncNow {
                    Button {
                        Task { await viewModel.syncNow(context: modelContext) }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
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
                        Label("Leave Family Sync", systemImage: "person.crop.circle.badge.minus")
                    }
                }

                if viewModel.state.status == .localOnly {
                    Text("Turn on iCloud Sync before creating or accepting a family share.")
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.state.canLeaveShare {
                Section("Leaving") {
                    Toggle("Delete local shared data when leaving", isOn: $deleteLocalDataOnLeave)
                    Text("Keeping local data leaves this device with a private copy. Deleting local data removes the synced Little Windows data from this device only.")
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
            await viewModel.refresh()
        }
        .task {
            await viewModel.refresh()
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
            "Leave Family Sync?",
            isPresented: $confirmLeave,
            titleVisibility: .visible
        ) {
            Button("Leave Family Sync", role: .destructive) {
                Task {
                    await viewModel.leaveShare(
                        context: modelContext,
                        deleteLocalData: deleteLocalDataOnLeave
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops syncing this device with the shared family data.")
        }
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
        ) {}

        func itemTitle(for csc: UICloudSharingController) -> String? {
            CloudKitSharingService.shared.shareTitle
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            CloudKitSharingService.shareIconData
        }

        func itemType(for csc: UICloudSharingController) -> String? {
            "com.debidia.LittleWindows.family-sync"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
