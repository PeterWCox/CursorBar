import Foundation
import AppKit

// MARK: - Per-project tasks (todos)
// Stored in .cursormetro/tasks.json; only tasks for the current project are shown in that project's Tasks view.

struct ProjectTask: Identifiable, Codable, Equatable {
    var id: UUID
    var content: String
    var createdAt: Date
    var completed: Bool
    /// When the task was marked completed; nil if not completed or completed before this field existed.
    var completedAt: Date?
    /// Relative path under .cursormetro (e.g. "screenshots/<id>.png") for task screenshot.
    var screenshotPath: String?

    init(id: UUID = UUID(), content: String, createdAt: Date = Date(), completed: Bool = false, completedAt: Date? = nil, screenshotPath: String? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.completed = completed
        self.completedAt = completedAt
        self.screenshotPath = screenshotPath
    }

    enum CodingKeys: String, CodingKey {
        case id, content, createdAt, completed, completedAt, screenshotPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completed = try c.decode(Bool.self, forKey: .completed)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        screenshotPath = try c.decodeIfPresent(String.self, forKey: .screenshotPath)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(screenshotPath, forKey: .screenshotPath)
    }
}

private struct ProjectTasksFile: Codable {
    var tasks: [ProjectTask]
}

enum ProjectTasksStorage {
    static func tasksURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursormetro")
            .appendingPathComponent("tasks.json")
    }

    /// Directory for task screenshots: .cursormetro/screenshots/
    static func screenshotsDirectoryURL(workspacePath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursormetro")
            .appendingPathComponent("screenshots", isDirectory: true)
    }

    /// Full file URL for a task's screenshot. Pass screenshotPath from the task (e.g. "screenshots/<id>.png").
    static func taskScreenshotFileURL(workspacePath: String, screenshotPath: String) -> URL {
        URL(fileURLWithPath: workspacePath)
            .appendingPathComponent(".cursormetro")
            .appendingPathComponent(screenshotPath)
    }

    private static func load(workspacePath: String) -> ProjectTasksFile {
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

    static func tasks(workspacePath: String) -> [ProjectTask] {
        load(workspacePath: workspacePath).tasks.sorted { $0.createdAt < $1.createdAt }
    }

    static func addTask(workspacePath: String, content: String, screenshotImage: NSImage? = nil) -> ProjectTask {
        var file = load(workspacePath: workspacePath)
        var task = ProjectTask(content: content)
        if let image = screenshotImage {
            let relPath = "screenshots/\(task.id.uuidString).png"
            let dir = screenshotsDirectoryURL(workspacePath: workspacePath)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("\(task.id.uuidString).png")
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                task.screenshotPath = relPath
            }
        }
        file.tasks.append(task)
        save(workspacePath: workspacePath, file)
        return task
    }

    static func updateTask(workspacePath: String, id: UUID, content: String? = nil, completed: Bool? = nil) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        if let content = content { file.tasks[index].content = content }
        if let completed = completed {
            file.tasks[index].completed = completed
            file.tasks[index].completedAt = completed ? Date() : nil
        }
        save(workspacePath: workspacePath, file)
    }

    /// Update only the task's screenshot: save image to .cursormetro/screenshots/<id>.png or remove if nil.
    static func updateTaskScreenshot(workspacePath: String, id: UUID, image: NSImage?) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        let relPath = "screenshots/\(id.uuidString).png"
        let dir = screenshotsDirectoryURL(workspacePath: workspacePath)
        let fileURL = dir.appendingPathComponent("\(id.uuidString).png")

        if let img = image {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
                file.tasks[index].screenshotPath = relPath
            }
        } else {
            if file.tasks[index].screenshotPath != nil {
                try? FileManager.default.removeItem(at: fileURL)
                file.tasks[index].screenshotPath = nil
            }
        }
        save(workspacePath: workspacePath, file)
    }

    static func deleteTask(workspacePath: String, id: UUID) {
        var file = load(workspacePath: workspacePath)
        guard let index = file.tasks.firstIndex(where: { $0.id == id }) else { return }
        if let path = file.tasks[index].screenshotPath {
            let url = taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            try? FileManager.default.removeItem(at: url)
        }
        file.tasks.removeAll { $0.id == id }
        save(workspacePath: workspacePath, file)
    }
}
