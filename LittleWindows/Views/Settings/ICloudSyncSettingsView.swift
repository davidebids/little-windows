import SwiftData
import SwiftUI

struct ICloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ICloudSyncSettingsViewModel()

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("iCloud Sync", value: viewModel.availability.title)
                LabeledContent("Apple Account", value: viewModel.accountStatusDescription)
                LabeledContent("Container", value: viewModel.containerStatusDescription)
                LabeledContent("Store") {
                    Text(PersistenceService.isUsingCloudKitStore ? "CloudKit private database" : "Local fallback")
                        .foregroundStyle(.secondary)
                }
                if let lastCheckedAt = viewModel.lastCheckedAt {
                    LabeledContent("Last checked", value: lastCheckedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let startupErrorMessage = viewModel.startupErrorMessage {
                    Text(startupErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("How sync works") {
                Text(viewModel.availability.detail)
                    .foregroundStyle(.secondary)
                Text("Syncing happens automatically when iCloud is available. Logging still works offline; local changes sync later.")
                    .foregroundStyle(.secondary)
                Text("Private iCloud Sync works across devices signed into your Apple Account.")
                    .foregroundStyle(.secondary)
            }

            if let diagnostics = viewModel.diagnostics {
                Section("Local data") {
                    LabeledContent("Profiles", value: "\(diagnostics.profileCount)")
                    LabeledContent("Active profiles", value: "\(diagnostics.activeProfileCount)")
                    LabeledContent("Records", value: "\(diagnostics.recordCounts.dropFirst().map(\.count).reduce(0, +))")
                    if let lastLocalSaveAt = diagnostics.lastLocalSaveAt {
                        LabeledContent("Last local save", value: lastLocalSaveAt.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        LabeledContent("Last local save", value: "Not recorded yet")
                    }
                    LabeledContent(
                        "Migration",
                        value: diagnostics.migrationState.hasMigratedLocalStoreToCloudKit ? "Complete" : "Not complete"
                    )
                    if let migrationCompletedAt = diagnostics.migrationState.migrationCompletedAt {
                        LabeledContent("Migrated at", value: migrationCompletedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                NavigationLink {
                    SyncDiagnosticsView(snapshot: diagnostics)
                } label: {
                    Label("Sync diagnostics", systemImage: "stethoscope")
                }
            }

            Section("Back up before testing") {
                Text("Use Settings > Data > Export JSON backup before changing CloudKit containers, resetting development data, or testing migrations on devices.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh(context: modelContext)
        }
        .task {
            await viewModel.refresh(context: modelContext)
        }
    }
}
