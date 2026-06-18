import CloudKit
import Foundation

@MainActor
final class CloudKitSharingService {
    private let containerIdentifier: String

    init(containerIdentifier: String = PersistenceService.iCloudContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
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
        _ = CKContainer(identifier: containerIdentifier)
        return .failure(FamilySharingNotImplementedError())
    }

    struct FamilySharingNotImplementedError: LocalizedError {
        var errorDescription: String? {
            "Family Sync requires a shared iCloud record zone and is not enabled yet."
        }
    }
}
