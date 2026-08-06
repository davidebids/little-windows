import Foundation
import WidgetKit

enum WatchSharedStorage {
    private static let lock = NSLock()

    static func readState() -> WatchCompanionState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(WatchCompanionState.self, from: data),
              state.schemaVersion == WatchCompanionProtocol.schemaVersion else {
            return .empty
        }
        return state
    }

    static func writeState(
        _ state: WatchCompanionState,
        reloadWidgets: Bool = true
    ) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        lock.lock()
        try? data.write(to: stateURL, options: .atomic)
        lock.unlock()
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func readOutbox() -> [WatchCommand] {
        lock.lock()
        defer { lock.unlock() }
        return loadOutbox()
    }

    static func enqueue(_ command: WatchCommand) {
        lock.lock()
        defer { lock.unlock() }
        var commands = loadOutbox()
        commands.removeAll { $0.id == command.id }
        commands.append(command)
        saveOutbox(commands)
    }

    static func removeCommand(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var commands = loadOutbox()
        commands.removeAll { $0.id == id }
        saveOutbox(commands)
    }

    private static var containerURL: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WatchCompanionProtocol.appGroupIdentifier
        ) ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LittleWindowsWatch", isDirectory: true)
    }

    private static var stateURL: URL {
        fileURL(WatchCompanionProtocol.stateFilename)
    }

    private static var outboxURL: URL {
        fileURL(WatchCompanionProtocol.outboxFilename)
    }

    private static func fileURL(_ filename: String) -> URL {
        try? FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true
        )
        return containerURL.appendingPathComponent(filename)
    }

    private static func loadOutbox() -> [WatchCommand] {
        guard let data = try? Data(contentsOf: outboxURL) else { return [] }
        return (try? JSONDecoder().decode([WatchCommand].self, from: data)) ?? []
    }

    private static func saveOutbox(_ commands: [WatchCommand]) {
        if commands.isEmpty {
            try? FileManager.default.removeItem(at: outboxURL)
            return
        }
        guard let data = try? JSONEncoder().encode(commands) else { return }
        try? data.write(to: outboxURL, options: .atomic)
    }
}
