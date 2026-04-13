import Foundation

enum TabManagerPersistence {
    private static let fileName = "cursor_plus_tabs.json"
    private static let saveQueue = DispatchQueue(label: "CursorPlus.TabManagerPersistence", qos: .utility)

    static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorPlus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> SavedTabState? {
        let data: Data
        do {
            data = try Data(contentsOf: saveURL)
        } catch {
            return nil
        }
        guard let state = try? JSONDecoder().decode(SavedTabState.self, from: data) else {
            return nil
        }
        if state.schemaVersion < SavedTabState.currentSchemaVersion {
            try? FileManager.default.removeItem(at: saveURL)
            return nil
        }
        return state
    }

    static func save(_ state: SavedTabState) {
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}
