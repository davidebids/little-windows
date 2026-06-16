import SwiftUI

struct SyncDiagnosticsView: View {
    let snapshot: SyncDiagnosticSnapshot

    var body: some View {
        List {
            Section("Counts") {
                ForEach(snapshot.recordCounts) { item in
                    LabeledContent(item.name, value: "\(item.count)")
                }
            }

            Section("Profile scope") {
                LabeledContent("Orphaned records", value: "\(snapshot.orphanedProfileScopedRecordCount)")
                LabeledContent("Duplicate child-name risk", value: "\(snapshot.duplicateChildProfileNameCount)")
                Text("Records with missing or unknown profile IDs are assigned to an existing child profile during migration when possible.")
                    .foregroundStyle(.secondary)
            }

            Section("Migration") {
                LabeledContent(
                    "Local to CloudKit",
                    value: snapshot.migrationState.hasMigratedLocalStoreToCloudKit ? "Complete" : "Not complete"
                )
                LabeledContent("Version", value: "\(snapshot.migrationState.migrationVersion)")
                if let migrationCompletedAt = snapshot.migrationState.migrationCompletedAt {
                    LabeledContent("Completed", value: migrationCompletedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let lastErrorMessage = snapshot.migrationState.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("CloudKit Dashboard checks") {
                Text("Verify record types in the private database development environment, then deploy the schema to production before TestFlight or App Store distribution.")
                    .foregroundStyle(.secondary)
                Text("Do not log or export private child data while inspecting CloudKit records.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sync Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
