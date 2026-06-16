import Foundation

enum IntegrationCommandStore {
    @MainActor private static var inAppHandler: ((URL) async -> Bool)?

    @MainActor
    static func installInAppHandler(
        _ handler: @escaping (URL) async -> Bool
    ) {
        inAppHandler = handler
    }

    @MainActor
    static func deliverToRunningApp(_ url: URL) async -> Bool {
        guard let inAppHandler else { return false }
        return await inAppHandler(url)
    }

    static func enqueue(_ url: URL) {
        let fileURL = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.pendingURLFilename
        )
        try? Data(url.absoluteString.utf8).write(to: fileURL, options: .atomic)
    }

    static func consumePendingURL() -> URL? {
        let fileURL = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.pendingURLFilename
        )
        guard let data = try? Data(contentsOf: fileURL),
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        try? FileManager.default.removeItem(at: fileURL)
        return URL(string: value)
    }

    static func clearPendingURL(matching url: URL) {
        let fileURL = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.pendingURLFilename
        )
        guard let data = try? Data(contentsOf: fileURL),
              String(data: data, encoding: .utf8) == url.absoluteString else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
