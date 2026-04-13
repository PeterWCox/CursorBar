import XCTest
import AppKit
@testable import Cursor_Metro

private struct EncodedTasksFile: Encodable {
    let tasks: [ProjectTask]
}

extension XCTestCase {
    func makeWorkspacePath() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorMetroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url.path
    }

    func writeTasks(_ tasks: [ProjectTask], workspacePath: String) throws {
        let file = EncodedTasksFile(tasks: tasks)
        let data = try JSONEncoder().encode(file)
        let url = ProjectTasksStorage.tasksURL(workspacePath: workspacePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func makeTestPNGData(color: NSColor = .systemRed, size: CGSize = CGSize(width: 8, height: 8)) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not create PNG test data")
        }

        return pngData
    }
}
