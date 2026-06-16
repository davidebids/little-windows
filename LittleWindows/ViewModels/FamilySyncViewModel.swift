import Combine
import Foundation

@MainActor
final class FamilySyncViewModel: ObservableObject {
    @Published private(set) var state = FamilyShareState(
        mode: .localOnly,
        ownerDescription: "Checking",
        participantDescription: "Checking",
        sharingIsImplemented: false,
        lastErrorMessage: nil
    )
    @Published private(set) var availability: ICloudSyncAvailability = .checking

    private let statusService = SyncStatusService()
    private let sharingService = CloudKitSharingService()

    func refresh() async {
        await statusService.refreshStatus()
        availability = statusService.availability
        state = sharingService.currentState(privateSyncAvailable: statusService.isICloudAvailable)
    }

    func startSharing() async {
        switch await sharingService.startFamilyShare() {
        case .success:
            await refresh()
        case .failure(let error):
            state.lastErrorMessage = error.localizedDescription
        }
    }
}
