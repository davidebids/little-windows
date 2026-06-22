import Combine
import CloudKit
import Foundation
import SwiftData

@MainActor
final class FamilySyncViewModel: ObservableObject {
    @Published private(set) var state = FamilyShareState(
        mode: .localOnly,
        syncMode: .localOnly,
        role: .none,
        status: .notConfigured,
        ownerDescription: "Checking",
        participantDescription: "Checking",
        sharingIsImplemented: false,
        participantCount: 0,
        lastSyncAt: nil,
        pendingUploadCount: 0,
        pendingDownloadCount: 0,
        canResumeShare: false,
        canCreateShare: false,
        canManageShare: false,
        canSyncNow: false,
        canLeaveShare: false,
        lastErrorMessage: nil
    )
    @Published private(set) var availability: ICloudSyncAvailability = .checking
    @Published private(set) var isSyncing = false
    @Published private(set) var syncStatusMessage: String?
    @Published var presentedShare: CKShare?

    private let statusService = SyncStatusService()
    private let sharingService = CloudKitSharingService.shared

    func refresh(force: Bool = false) async {
        await statusService.refreshStatus(force: force)
        availability = statusService.availability
        state = sharingService.currentState(privateSyncAvailable: statusService.isICloudAvailable)
    }

    func startSharing(context: ModelContext) async {
        do {
            presentedShare = try await sharingService.createFamilyShare(context: context)
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func resumeSharing(context: ModelContext) async {
        do {
            try await sharingService.resumeFamilyShare(context: context)
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func manageSharing() async {
        do {
            presentedShare = try await sharingService.existingShare()
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncStatusMessage = "Syncing shared family data..."
        defer { isSyncing = false }
        do {
            let changed = try await sharingService.syncNow(context: context, reason: .manual)
            await refresh()
            syncStatusMessage = changed
                ? "Shared family data is up to date."
                : "No new family sync changes."
        } catch {
            syncStatusMessage = nil
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func leaveShare(context: ModelContext, deleteLocalData: Bool) async {
        do {
            try await sharingService.leaveFamilyShare(
                context: context,
                deleteLocalData: deleteLocalData
            )
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }
}
