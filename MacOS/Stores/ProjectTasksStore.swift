import Foundation
import AppKit
import Combine

@MainActor
final class ProjectTasksStore: ObservableObject {
    @Published private var tasksByWorkspace: [String: [ProjectTask]] = [:]
    @Published private var deletedTasksByWorkspace: [String: [ProjectTask]] = [:]

    private var changeObserver: NSObjectProtocol?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: ProjectTasksStorage.didChangeNotification,
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
        guard tasksByWorkspace[normalizedPath] == nil || deletedTasksByWorkspace[normalizedPath] == nil else {
            return
        }
        reload(workspacePath: normalizedPath)
    }

    func reload(workspacePath: String) {
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        guard !normalizedPath.isEmpty else { return }
        tasksByWorkspace[normalizedPath] = ProjectTasksStorage.tasks(workspacePath: normalizedPath)
        deletedTasksByWorkspace[normalizedPath] = ProjectTasksStorage.deletedTasks(workspacePath: normalizedPath)
    }

    func tasks(for workspacePath: String) -> [ProjectTask] {
        ensureLoaded(workspacePath: workspacePath)
        return tasksByWorkspace[normalizedWorkspacePath(workspacePath)] ?? []
    }

    func deletedTasks(for workspacePath: String) -> [ProjectTask] {
        ensureLoaded(workspacePath: workspacePath)
        return deletedTasksByWorkspace[normalizedWorkspacePath(workspacePath)] ?? []
    }

    func task(for workspacePath: String, id: UUID) -> ProjectTask? {
        tasks(for: workspacePath).first { $0.id == id }
            ?? deletedTasks(for: workspacePath).first { $0.id == id }
    }

    func taskStatesByID(for workspacePath: String) -> [UUID: TaskState] {
        Dictionary(uniqueKeysWithValues: tasks(for: workspacePath).map { ($0.id, $0.taskState) })
    }

    @discardableResult
    func addTask(
        workspacePath: String,
        content: String,
        screenshotImages: [NSImage] = [],
        providerID: AgentProviderID = .cursor,
        modelId: String = AvailableModels.autoID,
        taskState: TaskState = .inProgress
    ) -> ProjectTask {
        let task = ProjectTasksStorage.addTask(
            workspacePath: workspacePath,
            content: content,
            screenshotImages: screenshotImages,
            providerID: providerID,
            modelId: modelId,
            taskState: taskState
        )
        reload(workspacePath: workspacePath)
        return task
    }

    func updateTask(workspacePath: String, id: UUID, content: String? = nil, taskState: TaskState? = nil, providerID: AgentProviderID? = nil, modelId: String? = nil) {
        ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: id, content: content, taskState: taskState, providerID: providerID, modelId: modelId)
        reload(workspacePath: workspacePath)
    }

    func deleteTask(workspacePath: String, id: UUID) {
        ProjectTasksStorage.deleteTask(workspacePath: workspacePath, id: id)
        reload(workspacePath: workspacePath)
    }

    func restoreTask(workspacePath: String, id: UUID) {
        ProjectTasksStorage.restoreTask(workspacePath: workspacePath, id: id)
        reload(workspacePath: workspacePath)
    }

    func permanentlyDeleteTask(workspacePath: String, id: UUID) {
        ProjectTasksStorage.permanentlyDeleteTask(workspacePath: workspacePath, id: id)
        reload(workspacePath: workspacePath)
    }

    func removeTaskScreenshot(workspacePath: String, id: UUID, screenshotPath: String) {
        ProjectTasksStorage.removeTaskScreenshot(workspacePath: workspacePath, id: id, screenshotPath: screenshotPath)
        reload(workspacePath: workspacePath)
    }

    func assignAgentTab(workspacePath: String, taskID: UUID, agentTabID: UUID) {
        ProjectTasksStorage.assignAgentTab(workspacePath: workspacePath, taskID: taskID, agentTabID: agentTabID)
        reload(workspacePath: workspacePath)
    }

    func clearAgentTab(workspacePath: String, taskID: UUID) {
        ProjectTasksStorage.clearAgentTab(workspacePath: workspacePath, taskID: taskID)
        reload(workspacePath: workspacePath)
    }

    func linkedAgentTabID(workspacePath: String, taskID: UUID) -> UUID? {
        ProjectTasksStorage.linkedAgentTabID(workspacePath: workspacePath, taskID: taskID)
    }

    private func normalizedWorkspacePath(_ workspacePath: String) -> String {
        workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
