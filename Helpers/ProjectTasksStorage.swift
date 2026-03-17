import Foundation
import AppKit

// MARK: - Per-project tasks (todos)
// Stored in .metro/tasks.json; only tasks for the current project are shown in that project's Tasks view.

enum TaskState: String, Codable, CaseIterable {
    case backlog
    case inProgress
    case completed
    case deleted
}

struct ProjectTask: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String
    var createdAt: Date
    /// Canonical lifecycle for the task. This is the only source of truth for top-level task state.
    var taskState: TaskState
    /// When the task was marked completed; nil if not completed or completed before this field existed.
    var completedAt: Date?
    /// When the task was deleted; nil if not deleted.
    var deletedAt: Date?
    /// Relative paths under .metro (e.g. "screenshots/<id>_0.png") for task screenshots. Empty = no screenshots.
    var screenshotPaths: [String]
    /// Agent provider to use when delegating this task.
    var providerID: AgentProviderID
    /// Model ID to use when sending this task to an agent (e.g. "auto", "gpt-5.4-medium"). Defaults to Auto.
    var modelId: String
    /// Preserves the last non-deleted state so soft-deleted tasks can be restored.
    var preDeletionTaskState: TaskState?
    /// Linked agent tab for this task when one has been created.
    var agentTabID: UUID?

    var completed: Bool { taskState == .completed }
    var deleted: Bool { taskState == .deleted }
    var backlog: Bool { taskState == .backlog }

    init(
        id: UUID = UUID(),
        content: String,
        createdAt: Date = Date(),
        taskState: TaskState? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        deleted: Bool = false,
        deletedAt: Date? = nil,
        screenshotPaths: [String] = [],
        providerID: AgentProviderID = .cursor,
        modelId: String = AvailableModels.autoID,
        backlog: Bool = false,
        preDeletionTaskState: TaskState? = nil,
        agentTabID: UUID? = nil
    ) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.taskState = taskState ?? Self.migratedTaskState(completed: completed, deleted: deleted, backlog: backlog)
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.screenshotPaths = screenshotPaths
        self.providerID = providerID
        self.modelId = modelId
        self.preDeletionTaskState = preDeletionTaskState
        self.agentTabID = agentTabID
    }

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, taskState, completed, completedAt, deleted, deletedAt, screenshotPath, screenshotPaths, providerID, modelId, backlog, preDeletionTaskState, agentTabID
    }

    private static func migratedTaskState(completed: Bool, deleted: Bool, backlog: Bool) -> TaskState {
        if deleted { return .deleted }
        if completed { return .completed }
        if backlog { return .backlog }
        return .inProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        let deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        let backlog = try c.decodeIfPresent(Bool.self, forKey: .backlog) ?? false
        taskState = try c.decodeIfPresent(TaskState.self, forKey: .taskState)
            ?? Self.migratedTaskState(completed: completed, deleted: deleted, backlog: backlog)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        if let paths = try c.decodeIfPresent([String].self, forKey: .screenshotPaths) {
            screenshotPaths = paths
        } else if let single = try c.decodeIfPresent(String.self, forKey: .screenshotPath) {
            screenshotPaths = [single]
        } else {
            screenshotPaths = []
        }
        let rawProviderID = try c.decodeIfPresent(String.self, forKey: .providerID)
        providerID = AgentProviders.resolvedProviderID(rawProviderID ?? AgentProviderID.cursor.rawValue)
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? AvailableModels.autoID
        preDeletionTaskState = try c.decodeIfPresent(TaskState.self, forKey: .preDeletionTaskState)
        agentTabID = try c.decodeIfPresent(UUID.self, forKey: .agentTabID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(taskState, forKey: .taskState)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(deleted, forKey: .deleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(screenshotPaths, forKey: .screenshotPaths)
        try c.encode(providerID, forKey: .providerID)
        try c.encode(modelId, forKey: .modelId)
        try c.encode(backlog, forKey: .backlog)
        try c.encodeIfPresent(preDeletionTaskState, forKey: .preDeletionTaskState)
        try c.encodeIfPresent(agentTabID, forKey: .agentTabID)
    }
}

private struct ProjectTasksFile: Codable {
    var tasks: [ProjectTask]
}

enum ProjectTasksStorage {
    static let didChangeNotification = Notification.Name("ProjectTasksStorageDidChange")
    private static var cachedFilesByWorkspace: [String: ProjectTasksFile] = [:]

    private static func normalizedWorkspacePath(_ workspacePath: String) -> String {
        workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func setTaskState(_ newState: TaskState, for task: inout ProjectTask) {
        let previousState = task.taskState
        guard previousState != newState else { return }

        switch newState {
        case .backlog, .inProgress:
            task.taskState = newState
            if previousState == .completed {
                task.completedAt = nil
            }
            if previousState == .deleted {
                task.deletedAt = nil
                task.preDeletionTaskState = nil
            }
        case .completed:
            task.taskState = .completed
            if previousState != .completed {
                task.completedAt = Date()
            }
            if previousState == .deleted {
                task.deletedAt = nil
                task.preDeletionTaskState = nil
            }
        case .deleted:
            task.preDeletionTaskState = previousState == .deleted ? task.preDeletionTaskState : previousState
            task.taskState = .deleted
            task.deletedAt = Date()
        }
    }

    static func tasksURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".metro")
            .appendingPathComponent("tasks.json")
    }

    /// Directory for task screenshots: .metro/screenshots/
    static func screenshotsDirectoryURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".metro")
            .appendingPathComponent("screenshots", isDirectory: true)
    }

    /// Full file URL for a task's screenshot. Pass screenshotPath from the task (e.g. "screenshots/<id>.png").
    static func taskScreenshotFileURL(workspacePath: String, screenshotPath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".metro")
            .appendingPathComponent(screenshotPath)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func persistScreenshotData(_ screenshotData: [Data], taskID: UUID, workspacePath: String) -> [String] {
        let dir = screenshotsDirectoryURL(workspacePath: workspacePath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var paths: [String] = []
        for (index, data) in screenshotData.enumerated() {
            let relPath = "screenshots/\(taskID.uuidString)_\(index).png"
            let fileURL = dir.appendingPathComponent("\(taskID.uuidString)_\(index).png")
            do {
                try data.write(to: fileURL, options: .atomic)
                ImageAssetCache.shared.removeScreenshot(for: fileURL)
                paths.append(relPath)
            } catch {
                continue
            }
        }
        return paths
    }

    private static func load(workspacePath: String) -> ProjectTasksFile {
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        if let cached = cachedFilesByWorkspace[normalizedPath] {
            return cached
        }

        migrateCursormetroToMetroIfNeeded(workspacePath: workspacePath)
        let url = tasksURL(workspacePath: workspacePath)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ProjectTasksFile.self, from: data) {
            cachedFilesByWorkspace[normalizedPath] = decoded
            return decoded
        }
        let empty = ProjectTasksFile(tasks: [])
        cachedFilesByWorkspace[normalizedPath] = empty
        return empty
    }

    private static func save(workspacePath: String, _ file: ProjectTasksFile) {
        let url = tasksURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
        let normalizedPath = normalizedWorkspacePath(workspacePath)
        cachedFilesByWorkspace[normalizedPath] = file
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: nil,
            userInfo: ["workspacePath": normalizedPath]
        )
    }

    /// Active tasks only (not deleted). Newest first so new tasks appear at top of In Review/Backlog.
    static func tasks(workspacePath: String) -> [ProjectTask] {
        load(workspacePath: workspacePath).tasks
            .filter { $0.taskState != .deleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func task(workspacePath: String, id: UUID) -> ProjectTask? {
        load(workspacePath: workspacePath).tasks.first { $0.id == id }
    }

    static func linkedAgentTabID(workspacePath: String, taskID: UUID) -> UUID? {
        task(workspacePath: workspacePath, id: taskID)?.agentTabID
    }

    static func taskLinkedToAgentTab(workspacePath: String, agentTabID: UUID) -> ProjectTask? {
        load(workspacePath: workspacePath).tasks.first { $0.agentTabID == agentTabID }
    }

    static func assignAgentTab(workspacePath: String, taskID: UUID, agentTabID: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        for taskIndex in file.tasks.indices where file.tasks[taskIndex].agentTabID == agentTabID {
            file.tasks[taskIndex].agentTabID = nil
        }
        file.tasks[index].agentTabID = agentTabID
        save(workspacePath: workspacePath, file)
    }

    static func clearAgentTab(workspacePath: String, taskID: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        file.tasks[index].agentTabID = nil
        save(workspacePath: workspacePath, file)
    }

    /// Soft-deleted tasks, newest first.
    static func deletedTasks(workspacePath: String) -> [ProjectTask] {
        load(workspacePath: workspacePath).tasks
            .filter { $0.taskState == .deleted }
            .sorted { ($0.deletedAt ?? .distantPast) >= ($1.deletedAt ?? .distantPast) }
    }

    static func addTask(workspacePath: String, content: String, screenshotData: [Data], providerID: AgentProviderID = .cursor, modelId: String = AvailableModels.autoID, taskState: TaskState = .inProgress) -> ProjectTask {
        var file = load(workspacePath: workspacePath)
        var task = ProjectTask(content: content, taskState: taskState, providerID: providerID, modelId: modelId)
        task.screenshotPaths = persistScreenshotData(screenshotData, taskID: task.id, workspacePath: workspacePath)
        file.tasks.insert(task, at: 0)
        save(workspacePath: workspacePath, file)
        return task
    }

    static func addTask(workspacePath: String, content: String, screenshotImages: [NSImage] = [], providerID: AgentProviderID = .cursor, modelId: String = AvailableModels.autoID, taskState: TaskState = .inProgress) -> ProjectTask {
        addTask(
            workspacePath: workspacePath,
            content: content,
            screenshotData: screenshotImages.compactMap(pngData(from:)),
            providerID: providerID,
            modelId: modelId,
            taskState: taskState
        )
    }

    static func updateTask(workspacePath: String, id: UUID, content: String? = nil, taskState: TaskState? = nil, providerID: AgentProviderID? = nil, modelId: String? = nil) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        if let content = content { file.tasks[index].content = content }
        if let taskState { setTaskState(taskState, for: &file.tasks[index]) }
        if let providerID { file.tasks[index].providerID = providerID }
        if let modelId = modelId { file.tasks[index].modelId = modelId }
        save(workspacePath: workspacePath, file)
    }

    /// Update the task's screenshots: save images to .metro/screenshots/<id>_0.png, _1.png, etc.; remove any old files not in the new set.
    static func updateTaskScreenshots(workspacePath: String, id: UUID, screenshotData: [Data]) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        let oldPaths = file.tasks[index].screenshotPaths
        let newPaths = persistScreenshotData(screenshotData, taskID: id, workspacePath: workspacePath)
        for oldPath in oldPaths where !newPaths.contains(oldPath) {
            let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: oldPath)
            ImageAssetCache.shared.removeScreenshot(for: url)
            try? FileManager.default.removeItem(at: url)
        }
        file.tasks[index].screenshotPaths = newPaths
        save(workspacePath: workspacePath, file)
    }

    static func updateTaskScreenshots(workspacePath: String, id: UUID, images: [NSImage]) {
        updateTaskScreenshots(
            workspacePath: workspacePath,
            id: id,
            screenshotData: images.compactMap(pngData(from:))
        )
    }

    /// Remove one screenshot by path and delete its file.
    static func removeTaskScreenshot(workspacePath: String, id: UUID, screenshotPath: String) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        file.tasks[index].screenshotPaths.removeAll { $0 == screenshotPath }
        let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
        ImageAssetCache.shared.removeScreenshot(for: url)
        try? FileManager.default.removeItem(at: url)
        save(workspacePath: workspacePath, file)
    }

    /// Soft-delete: mark task as deleted so it appears in the Deleted section.
    static func deleteTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        setTaskState(.deleted, for: &file.tasks[index])
        save(workspacePath: workspacePath, file)
    }

    /// Restore a soft-deleted task so it appears in Todo or Completed again.
    static func restoreTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        let restoredState = file.tasks[index].preDeletionTaskState
            ?? (file.tasks[index].completedAt != nil ? .completed : .inProgress)
        file.tasks[index].taskState = restoredState
        file.tasks[index].deletedAt = nil
        file.tasks[index].preDeletionTaskState = nil
        save(workspacePath: workspacePath, file)
    }

    /// Permanently remove a task and its screenshots (e.g. from the Deleted section).
    static func permanentlyDeleteTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        for path in file.tasks[index].screenshotPaths {
            let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            ImageAssetCache.shared.removeScreenshot(for: url)
            try? FileManager.default.removeItem(at: url)
        }
        file.tasks.removeAll { $0.id == id }
        save(workspacePath: workspacePath, file)
    }
}
