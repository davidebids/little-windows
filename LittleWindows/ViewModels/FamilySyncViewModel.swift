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
        canCreateShare: false,
        canManageShare: false,
        canSyncNow: false,
        canLeaveShare: false,
        lastErrorMessage: nil
    )
    @Published private(set) var availability: ICloudSyncAvailability = .checking
    @Published var presentedShare: CKShare?

    private let statusService = SyncStatusService()
    private let sharingService = CloudKitSharingService.shared

    func refresh() async {
        await statusService.refreshStatus()
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

    func manageSharing() async {
        do {
            presentedShare = try await sharingService.existingShare()
            await refresh()
        } catch {
            state.lastErrorMessage = error.localizedDescription
        }
    }

    func syncNow(context: ModelContext) async {
        do {
            try await sharingService.syncNow(context: context, reason: .manual)
            await refresh()
        } catch {
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
