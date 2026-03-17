import Foundation
import Combine

struct ProjectSettingsSnapshot: Equatable {
    var debugURL: String
    var startupScripts: [String]

    static let empty = ProjectSettingsSnapshot(debugURL: "", startupScripts: [])
}

@MainActor
final class ProjectSettingsStore: ObservableObject {
    @Published private var snapshotsByWorkspace: [String: ProjectSettingsSnapshot] = [:]

    private var changeObserver: NSObjectProtocol?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: ProjectSettingsStorage.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let workspacePath = notification.userInfo?["workspacePath"] as? String else { return }
            self?.reload(workspacePath: workspacePath)
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func ensureLoaded(workspacePath: String) {
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        guard snapshotsByWorkspace[normalizedPath] == nil else { return }
        reload(workspacePath: normalizedPath)
    }

    func reload(workspacePath: String) {
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        guard !normalizedPath.isEmpty else { return }
        snapshotsByWorkspace[normalizedPath] = ProjectSettingsSnapshot(
            debugURL: ProjectSettingsStorage.getDebugURL(workspacePath: normalizedPath) ?? "",
            startupScripts: ProjectSettingsStorage.getStartupScripts(workspacePath: normalizedPath)
        )
    }

    func snapshot(for workspacePath: String) -> ProjectSettingsSnapshot {
        ensureLoaded(workspacePath: workspacePath)
        return snapshotsByWorkspace[normalizedWorkspacePath(workspacePath)] ?? .empty
    }

    func debugURL(for workspacePath: String) -> String? {
        let value = snapshot(for: workspacePath).debugURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func startupScripts(for workspacePath: String) -> [String] {
        snapshot(for: workspacePath).startupScripts
    }

    func setDebugURL(workspacePath: String, _ value: String?) {
        ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, value)
        reload(workspacePath: workspacePath)
    }

    func setStartupScripts(workspacePath: String, _ scripts: [String]) {
        ProjectSettingsStorage.setStartupScripts(workspacePath: workspacePath, scripts)
        reload(workspacePath: workspacePath)
    }

    private func normalizedWorkspacePath(_ workspacePath: String) -> String {
        workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
