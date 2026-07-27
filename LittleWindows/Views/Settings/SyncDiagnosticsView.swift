import SwiftData
import SwiftUI

struct SyncDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: SyncDiagnosticSnapshot?

    init(snapshot: SyncDiagnosticSnapshot? = nil) {
        _snapshot = State(initialValue: snapshot)
    }

    var body: some View {
        Group {
            if let snapshot {
                List {
                    diagnosticsContent(snapshot)
                }
            } else {
                List {
                    ProgressView("Loading sync diagnostics")
                }
            }
        }
        .navigationTitle("Sync Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard snapshot == nil else { return }
            await Task.yield()
            snapshot = SyncDiagnosticsService.snapshot(context: modelContext)
        }
    }

    @ViewBuilder
    private func diagnosticsContent(_ snapshot: SyncDiagnosticSnapshot) -> some View {
        Section("Counts") {
            ForEach(snapshot.recordCounts) { item in
                LabeledContent(item.name, value: "\(item.count)")
            }
        }
        .labeledContentStyle(AdaptiveLabeledContentStyle())

        Section("Profile scope") {
            LabeledContent("Orphaned records", value: "\(snapshot.orphanedProfileScopedRecordCount)")
            LabeledContent("Duplicate child-name risk", value: "\(snapshot.duplicateChildProfileNameCount)")
            Text("Records with missing or unknown profile IDs are assigned to an existing child profile during migration when possible.")
                .foregroundStyle(.secondary)
        }
        .labeledContentStyle(AdaptiveLabeledContentStyle())

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
        .labeledContentStyle(AdaptiveLabeledContentStyle())

        Section("CloudKit push delivery") {
            LabeledContent(
                "Device registration",
                value: snapshot.isRegisteredForRemoteNotifications
                    ? "Registered"
                    : "Not registered"
            )
            if let registeredAt = snapshot.lastRemoteNotificationRegistrationAt {
                LabeledContent(
                    "Last attempt",
                    value: registeredAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            if let error = snapshot.lastRemoteNotificationRegistrationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                Text("CloudKit uses this registration to wake Little Windows when shared data changes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .labeledContentStyle(AdaptiveLabeledContentStyle())

    }
}
