import Foundation
import AppKit

// MARK: - Per-project tasks (todos)
// Stored in .metro/tasks.json; only tasks for the current project are shown in that project's Tasks view.

struct ProjectTask: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String
    var createdAt: Date
    var completed: Bool
    /// When the task was marked completed; nil if not completed or completed before this field existed.
    var completedAt: Date?
    /// When true, task is soft-deleted and shown in the Deleted section. When false, task is active or completed.
    var deleted: Bool
    /// When the task was deleted; nil if not deleted.
    var deletedAt: Date?
    /// Relative paths under .metro (e.g. "screenshots/<id>_0.png") for task screenshots. Empty = no screenshots.
    var screenshotPaths: [String]
    /// Model ID to use when sending this task to an agent (e.g. "auto", "gpt-5.4-medium"). Defaults to Auto.
    var modelId: String
    /// When true, task appears in Backlog section instead of Todo (only for non-completed tasks).
    var backlog: Bool
    /// Linked agent tab for this task when one has been created.
    var agentTabID: UUID?

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(), completed: Bool = false, completedAt: Date? = nil, deleted: Bool = false, deletedAt: Date? = nil, screenshotPaths: [String] = [], modelId: String = AvailableModels.autoID, backlog: Bool = false, agentTabID: UUID? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.completed = completed
        self.completedAt = completedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
        self.screenshotPaths = screenshotPaths
        self.modelId = modelId
        self.backlog = backlog
        self.agentTabID = agentTabID
    }

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, completed, completedAt, deleted, deletedAt, screenshotPath, screenshotPaths, modelId, backlog, agentTabID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completed = try c.decode(Bool.self, forKey: .completed)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        if let paths = try c.decodeIfPresent([String].self, forKey: .screenshotPaths) {
            screenshotPaths = paths
        } else if let single = try c.decodeIfPresent(String.self, forKey: .screenshotPath) {
            screenshotPaths = [single]
        } else {
            screenshotPaths = []
        }
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? AvailableModels.autoID
        backlog = try c.decodeIfPresent(Bool.self, forKey: .backlog) ?? false
        agentTabID = try c.decodeIfPresent(UUID.self, forKey: .agentTabID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(deleted, forKey: .deleted)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(screenshotPaths, forKey: .screenshotPaths)
        try c.encode(modelId, forKey: .modelId)
        try c.encode(backlog, forKey: .backlog)
        try c.encodeIfPresent(agentTabID, forKey: .agentTabID)
    }
}

private struct ProjectTasksFile: Codable {
    var tasks: [ProjectTask]
}

enum ProjectTasksStorage {
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

    private static func load(workspacePath: String) -> ProjectTasksFile {
        migrateCursormetroToMetroIfNeeded(workspacePath: workspacePath)
        let url = tasksURL(workspacePath: workspacePath)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ProjectTasksFile.self, from: data) {
            return decoded
        }
        return ProjectTasksFile(tasks: [])
    }

    private static func save(workspacePath: String, _ file: ProjectTasksFile) {
        let url = tasksURL(workspacePath: workspacePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url)
    }

    /// Active tasks only (not deleted). Newest first so new tasks appear at top of In Review/Backlog.
    static func tasks(workspacePath: String) -> [ProjectTask] {
        load(workspacePath: workspacePath).tasks
            .filter { !$0.deleted }
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
            .filter(\.deleted)
            .sorted { ($0.deletedAt ?? .distantPast) >= ($1.deletedAt ?? .distantPast) }
    }

    static func addTask(workspacePath: String, content: String, screenshotImages: [NSImage] = [], modelId: String = AvailableModels.autoID, backlog: Bool = false) -> ProjectTask {
        var file = load(workspacePath: workspacePath)
        var task = ProjectTask(content: content, modelId: modelId, backlog: backlog)
        let dir = screenshotsDirectoryURL(workspacePath: workspacePath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for (index, image) in screenshotImages.enumerated() {
            let relPath = "screenshots/\(task.id.uuidString)_\(index).png"
            let fileURL = dir.appendingPathComponent("\(task.id.uuidString)_\(index).png")
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                paths.append(relPath)
            }
        }
        task.screenshotPaths = paths
        file.tasks.insert(task, at: 0)
        save(workspacePath: workspacePath, file)
        return task
    }

    static func updateTask(workspacePath: String, id: UUID, content: String? = nil, completed: Bool? = nil, modelId: String? = nil, backlog: Bool? = nil) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        if let content = content { file.tasks[index].content = content }
        if let completed = completed {
            file.tasks[index].completed = completed
            file.tasks[index].completedAt = completed ? Date() : nil
        }
        if let modelId = modelId { file.tasks[index].modelId = modelId }
        if let backlog = backlog { file.tasks[index].backlog = backlog }
        save(workspacePath: workspacePath, file)
    }

    /// Update the task's screenshots: save images to .metro/screenshots/<id>_0.png, _1.png, etc.; remove any old files not in the new set.
    static func updateTaskScreenshots(workspacePath: String, id: UUID, images: [NSImage]) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        let dir = screenshotsDirectoryURL(workspacePath: workspacePath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let oldPaths = file.tasks[index].screenshotPaths
        var newPaths: [String] = []
        for (i, img) in images.enumerated() {
            let relPath = "screenshots/\(id.uuidString)_\(i).png"
            let fileURL = dir.appendingPathComponent("\(id.uuidString)_\(i).png")
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                newPaths.append(relPath)
            }
        }
        for oldPath in oldPaths where !newPaths.contains(oldPath) {
            let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: oldPath)
            try? FileManager.default.removeItem(at: url)
        }
        file.tasks[index].screenshotPaths = newPaths
        save(workspacePath: workspacePath, file)
    }

    /// Remove one screenshot by path and delete its file.
    static func removeTaskScreenshot(workspacePath: String, id: UUID, screenshotPath: String) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        file.tasks[index].screenshotPaths.removeAll { $0 == screenshotPath }
        let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
        try? FileManager.default.removeItem(at: url)
        save(workspacePath: workspacePath, file)
    }

    /// Soft-delete: mark task as deleted so it appears in the Deleted section.
    static func deleteTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        file.tasks[index].deleted = true
        file.tasks[index].deletedAt = Date()
        save(workspacePath: workspacePath, file)
    }

    /// Restore a soft-deleted task so it appears in Todo or Completed again.
    static func restoreTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        file.tasks[index].deleted = false
        file.tasks[index].deletedAt = nil
        save(workspacePath: workspacePath, file)
    }

    /// Permanently remove a task and its screenshots (e.g. from the Deleted section).
    static func permanentlyDeleteTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        for path in file.tasks[index].screenshotPaths {
            let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            try? FileManager.default.removeItem(at: url)
        }
        file.tasks.removeAll { $0.id == id }
        save(workspacePath: workspacePath, file)
    }
}
