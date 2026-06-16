import CloudKit
import Foundation

@MainActor
final class CloudKitSharingService {
    private let container: CKContainer

    init(containerIdentifier: String = PersistenceService.iCloudContainerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
    }

    func currentState(privateSyncAvailable: Bool) -> FamilyShareState {
        FamilyShareState(
            mode: privateSyncAvailable ? .privateICloudSync : .localOnly,
            ownerDescription: "Not sharing a family record zone",
            participantDescription: "No accepted family share",
            sharingIsImplemented: false,
            lastErrorMessage: nil
        )
    }

    func startFamilyShare() async -> Result<CKShare, Error> {
        .failure(FamilySharingNotImplementedError())
    }

    struct FamilySharingNotImplementedError: LocalizedError {
        var errorDescription: String? {
            "Family Sync requires a shared iCloud record zone and is not enabled yet."
        }
    }
}
