import SwiftUI

struct FamilySyncSettingsView: View {
    @StateObject private var viewModel = FamilySyncViewModel()

    var body: some View {
        List {
            Section("Current mode") {
                LabeledContent("Mode", value: viewModel.state.mode.displayName)
                LabeledContent("Owner", value: viewModel.state.ownerDescription)
                LabeledContent("Participant", value: viewModel.state.participantDescription)
            }

            Section("Private vs family sync") {
                Text("Private iCloud Sync works across devices signed into your Apple Account.")
                    .foregroundStyle(.secondary)
                Text("Family Sync lets another iCloud user, like a co-parent or caregiver, access the same Little Windows data.")
                    .foregroundStyle(.secondary)
                Text("Family Sync requires accepting an iCloud share invitation.")
                    .foregroundStyle(.secondary)
            }

            Section("Family sharing") {
                if viewModel.state.sharingIsImplemented {
                    Button("Share with caregiver", systemImage: "person.crop.circle.badge.plus") {
                        Task { await viewModel.startSharing() }
                    }
                } else {
                    LabeledContent("Status", value: "Not enabled")
                    Text("Family Sync requires a shared iCloud record zone and is not enabled yet.")
                        .foregroundStyle(.secondary)
                    Text("The next implementation step is to create a CloudKit root family record, include profile-scoped records under that shared scope, present UICloudSharingController, and handle share acceptance.")
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.state.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Family Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.refresh()
        }
    }
}
