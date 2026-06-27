import Combine
import CloudKit
import Foundation
import SwiftData

enum FamilySyncOperation: Equatable {
    case create
    case resume
    case manage
    case sync
    case leave

    var statusText: String {
        switch self {
        case .create:
            return "Creating the iCloud family share..."
        case .resume:
            return "Turning on Family Sync..."
        case .manage:
            return "Opening caregiver management..."
        case .sync:
            return "Syncing shared family data..."
        case .leave:
            return "Leaving Family Sync..."
        }
    }
}

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
        lastAcceptanceMessage: nil,
        lastErrorMessage: nil
    )
    @Published private(set) var availability: ICloudSyncAvailability = .checking
    @Published private(set) var isSyncing = false
    @Published private(set) var syncStatusMessage: String?
    @Published private(set) var activeOperation: FamilySyncOperation?
    @Published var presentedShare: CKShare?

    private let statusService = SyncStatusService()
    private let sharingService = CloudKitSharingService.shared

    func refresh(force: Bool = false) async {
        await statusService.refreshStatus(force: force)
        availability = statusService.availability
        state = sharingService.currentState(privateSyncAvailable: statusService.isICloudAvailable)
    }

    func startSharing(context: ModelContext) async {
        guard activeOperation == nil else { return }
        activeOperation = .create
        clearActionError()
        await Task.yield()
        defer { activeOperation = nil }
        do {
            presentedShare = try await sharingService.createFamilyShare(context: context)
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func resumeSharing(context: ModelContext) async {
        guard activeOperation == nil else { return }
        activeOperation = .resume
        clearActionError()
        await Task.yield()
        defer { activeOperation = nil }
        do {
            try await sharingService.resumeFamilyShare(context: context)
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func manageSharing() async {
        guard activeOperation == nil else { return }
        activeOperation = .manage
        clearActionError()
        await Task.yield()
        defer { activeOperation = nil }
        do {
            presentedShare = try await sharingService.existingShare()
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext) async {
        guard activeOperation == nil, !isSyncing else { return }
        activeOperation = .sync
        isSyncing = true
        syncStatusMessage = "Syncing shared family data..."
        clearActionError()
        await Task.yield()
        defer {
            isSyncing = false
            activeOperation = nil
        }
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
        guard activeOperation == nil else { return }
        activeOperation = .leave
        clearActionError()
        await Task.yield()
        defer { activeOperation = nil }
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

    private func clearActionError() {
        state.lastErrorMessage = nil
    }
}
