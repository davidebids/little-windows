import SwiftData
import SwiftUI

struct ICloudSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = ICloudSyncSettingsViewModel()

    var body: some View {
        List {
            Section("Sync mode") {
                Toggle(
                    "iCloud Sync",
                    isOn: Binding(
                        get: { viewModel.isICloudSyncEnabled },
                        set: { enabled in
                            viewModel.setICloudSyncEnabled(enabled)
                            Task { await viewModel.refresh(context: modelContext) }
                        }
                    )
                )

                Text(viewModel.isICloudSyncEnabled ? "Use private iCloud Sync for devices signed into the same Apple Account." : "Keep Little Windows data local to this device.")
                    .foregroundStyle(.secondary)

                if viewModel.requiresRestart {
                    Label("Restart Little Windows to apply this sync mode.", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

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
                if viewModel.isICloudSyncEnabled {
                    Text("Syncing happens automatically when iCloud is available. Logging still works offline; local changes sync later.")
                        .foregroundStyle(.secondary)
                    Text("Private iCloud Sync works across devices signed into your Apple Account.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("When iCloud Sync is off, Little Windows opens a local-only store and does not check the CloudKit container.")
                        .foregroundStyle(.secondary)
                    Text("Turn iCloud Sync back on and restart the app when you want same-Apple-Account sync again.")
                        .foregroundStyle(.secondary)
                }
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
