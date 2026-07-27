import Foundation
import WidgetKit

enum IntegrationCommandStore {
    @MainActor private static var inAppHandler: ((URL) async -> Bool)?
    private static let queueLock = NSLock()
    private static let maximumQueueDepth = 20
    private static let standardLifetime: TimeInterval = 5 * 60
    private static let timerMutationLifetime: TimeInterval = 30
    private static let requestedAtQueryName = "requestedAt"

    private struct PendingCommand: Codable {
        var id: UUID
        var urlString: String
        var createdAt: Date
        var expiresAt: Date
    }

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

    @discardableResult
    static func enqueue(_ url: URL, at date: Date = Date()) -> URL {
        let now = date
        let commandURL = isTimerMutation(url)
            ? timestamped(url, requestedAt: now)
            : url
        queueLock.lock()
        var queue = loadQueue().filter { $0.expiresAt > now }
        let identity = commandIdentity(commandURL)
        queue.removeAll {
            URL(string: $0.urlString).map(commandIdentity) == identity
        }
        let lifetime = isTimerMutation(commandURL) ? timerMutationLifetime : standardLifetime
        queue.append(PendingCommand(
            id: UUID(),
            urlString: commandURL.absoluteString,
            createdAt: now,
            expiresAt: now.addingTimeInterval(lifetime)
        ))
        if queue.count > maximumQueueDepth {
            queue.removeFirst(queue.count - maximumQueueDepth)
        }
        saveQueue(queue)
        queueLock.unlock()
        applyOptimisticTimerStop(commandURL, requestedAt: now)
        return commandURL
    }

    static func consumePendingURL() -> URL? {
        queueLock.lock()
        defer { queueLock.unlock() }
        let now = Date()
        var queue = loadQueue().filter { $0.expiresAt > now }
        guard !queue.isEmpty else {
            saveQueue([])
            return nil
        }
        let command = queue.removeFirst()
        saveQueue(queue)
        return URL(string: command.urlString)
    }

    static func clearPendingURL(matching url: URL) {
        queueLock.lock()
        defer { queueLock.unlock() }
        var queue = loadQueue()
        let identity = commandIdentity(url)
        queue.removeAll {
            URL(string: $0.urlString).map(commandIdentity) == identity
        }
        saveQueue(queue)
    }

    static func requestedAt(
        forTimerMutationURL url: URL,
        now: Date = Date()
    ) -> Date? {
        guard isTimerMutation(url) else { return nil }
        let rawValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == requestedAtQueryName })?
            .value
        guard let rawValue else { return now }
        guard let interval = TimeInterval(rawValue) else { return nil }
        let requestedAt = Date(timeIntervalSince1970: interval)
        guard requestedAt <= now.addingTimeInterval(5),
              now.timeIntervalSince(requestedAt) <= timerMutationLifetime else {
            return nil
        }
        return requestedAt
    }

    private static var fileURL: URL {
        SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.pendingURLFilename
        )
    }

    private static func loadQueue() -> [PendingCommand] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let queue = try? JSONDecoder().decode([PendingCommand].self, from: data) {
            return queue
        }
        guard let value = String(data: data, encoding: .utf8),
              URL(string: value) != nil else {
            return []
        }
        let now = Date()
        return [PendingCommand(
            id: UUID(),
            urlString: value,
            createdAt: now,
            expiresAt: now.addingTimeInterval(standardLifetime)
        )]
    }

    private static func saveQueue(_ queue: [PendingCommand]) {
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func timestamped(_ url: URL, requestedAt: Date) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == requestedAtQueryName }
        queryItems.append(URLQueryItem(
            name: requestedAtQueryName,
            value: String(requestedAt.timeIntervalSince1970)
        ))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private static func commandIdentity(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.filter {
            $0.name != requestedAtQueryName
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func applyOptimisticTimerStop(_ url: URL, requestedAt: Date) {
        let path = timerMutationPath(url)
        let targetID: UUID?
        if path == ["action", "stop-active"] {
            targetID = nil
        } else if path.count == 3,
                  path[0] == "action",
                  path[1] == "stop" {
            targetID = UUID(uuidString: path[2])
        } else {
            return
        }

        let snapshotURL = SystemIntegrationConstants.sharedFileURL(
            SystemIntegrationConstants.widgetSnapshotFilename
        )
        guard let data = try? Data(contentsOf: snapshotURL),
              var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              var timer = snapshot.activeTimer,
              timer.resolvedIsRunning,
              targetID.map({ $0 == timer.id }) ?? true else {
            return
        }

        timer.elapsedSeconds = max(
            timer.resolvedElapsedSeconds,
            requestedAt.timeIntervalSince(timer.startDate)
        )
        if let sideStart = timer.activeNursingSideTimerStartDate {
            let sideElapsed = max(0, requestedAt.timeIntervalSince(sideStart))
            switch timer.activeNursingSide {
            case .left:
                timer.leftDurationSeconds = max(timer.leftDurationSeconds, sideElapsed)
            case .right:
                timer.rightDurationSeconds = max(timer.rightDurationSeconds, sideElapsed)
            case .none:
                break
            }
        }
        timer.isRunning = false
        timer.activeNursingSideTimerStartDate = nil
        snapshot.generatedAt = requestedAt
        snapshot.activeTimer = timer
        guard let updatedData = try? JSONEncoder().encode(snapshot),
              (try? updatedData.write(to: snapshotURL, options: .atomic)) != nil else {
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func timerMutationPath(_ url: URL) -> [String] {
        var path = [url.host].compactMap { $0 }
            + url.pathComponents.filter { $0 != "/" }
        if path.count >= 2,
           path[0] == "profile",
           UUID(uuidString: path[1]) != nil {
            path.removeFirst(2)
        }
        return path
    }

    private static func isTimerMutation(_ url: URL) -> Bool {
        let path = timerMutationPath(url)
        return path.contains("action")
            && (path.contains("stop-active")
                || path.contains("stop")
                || path.contains("resume")
                || path.contains("switch-side"))
    }
}
