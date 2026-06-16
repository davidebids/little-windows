import CloudKit
import Combine
import Foundation

@MainActor
final class SyncService: ObservableObject {
    enum AccountState: Equatable {
        case checking
        case available
        case unavailable(String)

        var description: String {
            switch self {
            case .checking: "Checking iCloud..."
            case .available: "iCloud account available"
            case .unavailable(let reason): reason
            }
        }
    }

    @Published private(set) var accountState: AccountState = .checking

    // Local-first in v1. Enable the iCloud capability and switch the app's
    // ModelConfiguration to CloudKit after selecting a production container.
    let sharedFamilySyncEnabled = false

    func refresh() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                accountState = .available
            case .noAccount:
                accountState = .unavailable("No iCloud account is signed in")
            case .restricted:
                accountState = .unavailable("iCloud access is restricted")
            case .couldNotDetermine:
                accountState = .unavailable("iCloud account status could not be determined")
            case .temporarilyUnavailable:
                accountState = .unavailable("iCloud is temporarily unavailable")
            @unknown default:
                accountState = .unavailable("Unknown iCloud account state")
            }
        } catch {
            accountState = .unavailable("Unable to check iCloud: \(error.localizedDescription)")
        }
    }
}
