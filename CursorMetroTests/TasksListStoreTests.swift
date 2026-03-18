import XCTest
@testable import Cursor_Metro

final class TasksListStoreTests: XCTestCase {
    @MainActor
    func testConfigureBuildsSnapshotSectionsFromTasksAndStatuses() throws {
        let workspacePath = try makeWorkspacePath()
        let now = Date()

        let backlog = ProjectTask(
            content: "Backlog",
            createdAt: now.addingTimeInterval(-10),
            taskState: .backlog
        )
        let review = ProjectTask(
            content: "Review",
            createdAt: now.addingTimeInterval(-20),
            taskState: .inProgress
        )
        let stopped = ProjectTask(
            content: "Stopped",
            createdAt: now.addingTimeInterval(-30),
            taskState: .inProgress
        )
        let processing = ProjectTask(
            content: "Processing",
            createdAt: now.addingTimeInterval(-40),
            taskState: .inProgress
        )
        let todo = ProjectTask(
            content: "Todo",
            createdAt: now.addingTimeInterval(-50),
            taskState: .inProgress
        )
        let recentCompleted = ProjectTask(
            content: "Recent Completed",
            createdAt: now.addingTimeInterval(-60),
            taskState: .completed,
            completedAt: now.addingTimeInterval(-3600)
        )
        let oldCompleted = ProjectTask(
            content: "Old Completed",
            createdAt: now.addingTimeInterval(-70),
            taskState: .completed,
            completedAt: now.addingTimeInterval(-(3 * 24 * 60 * 60))
        )
        let deleted = ProjectTask(
            content: "Deleted",
            createdAt: now.addingTimeInterval(-80),
            taskState: .deleted,
            deletedAt: now.addingTimeInterval(-600),
            preDeletionTaskState: .inProgress
        )

        try writeTasks(
            [backlog, review, stopped, processing, todo, recentCompleted, oldCompleted, deleted],
            workspacePath: workspacePath
        )

        let store = TasksListStore()
        store.configure(
            workspacePath: workspacePath,
            linkedStatuses: [
                review.id: .review,
                stopped.id: .stopped,
                processing.id: .processing
            ]
        )

        XCTAssertEqual(store.snapshot.counts.backlog, 1)
        XCTAssertEqual(store.snapshot.counts.inProgress, 4)
        XCTAssertEqual(store.snapshot.counts.completed, 2)
        XCTAssertEqual(store.snapshot.counts.deleted, 1)

        XCTAssertEqual(store.snapshot.reviewRows.map(\.task.id), [review.id])
        XCTAssertEqual(store.snapshot.stoppedRows.map(\.task.id), [stopped.id])
        XCTAssertEqual(store.snapshot.processingRows.map(\.task.id), [processing.id])
        XCTAssertEqual(store.snapshot.todoRows.map(\.task.id), [todo.id])

        XCTAssertEqual(store.snapshot.visibleCompletedTasks.map(\.id), [recentCompleted.id, oldCompleted.id])
        XCTAssertEqual(store.snapshot.completedGrouped.map(\.title), ["Today", "Last 7 Days"])
        XCTAssertEqual(store.snapshot.deletedGrouped.map(\.title), ["Today"])
    }

    @MainActor
    func testConfigureResetsTransientStateWhenWorkspaceChanges() throws {
        let firstWorkspace = try makeWorkspacePath()
        let secondWorkspace = try makeWorkspacePath()

        let store = TasksListStore()
        store.configure(workspacePath: firstWorkspace, linkedStatuses: [:])
        store.showNewTaskComposer(selecting: .backlog)
        store.newTaskDraft = "Draft"
        store.newTaskModelId = "custom-model"
        store.expandedCompletedSections = ["Older"]
        store.expandedDeletedSections = ["Older"]

        store.configure(workspacePath: secondWorkspace, linkedStatuses: [:])

        XCTAssertFalse(store.isAddingNewTask)
        XCTAssertEqual(store.newTaskDraft, "")
        XCTAssertEqual(store.newTaskModelId, AvailableModels.autoID)
        XCTAssertEqual(store.expandedCompletedSections, ["Today"])
        XCTAssertEqual(store.expandedDeletedSections, ["Today"])
        XCTAssertEqual(store.selectedTasksTab, .inProgress)
    }

    @MainActor
    func testCommitNewTaskPersistsMultipleScreenshots() throws {
        let workspacePath = try makeWorkspacePath()
        let firstScreenshot = try makeTestPNGData(color: .systemRed)
        let secondScreenshot = try makeTestPNGData(color: .systemBlue)

        let store = TasksListStore()
        store.configure(workspacePath: workspacePath, linkedStatuses: [:])
        store.showNewTaskComposer(selecting: .inProgress)
        store.newTaskDraft = "Task with screenshots"

        store.commitNewTask(screenshotData: [firstScreenshot, secondScreenshot], providerID: .cursor)

        let tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].content, "Task with screenshots")
        XCTAssertEqual(tasks[0].screenshotPaths.count, 2)
        XCTAssertFalse(store.isAddingNewTask)

        for path in tasks[0].screenshotPaths {
            let url = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @MainActor
    func testCommitEditReplacesScreenshotSet() throws {
        let workspacePath = try makeWorkspacePath()
        let originalTask = ProjectTasksStorage.addTask(
            workspacePath: workspacePath,
            content: "Original",
            screenshotData: [
                try makeTestPNGData(color: .systemRed),
                try makeTestPNGData(color: .systemBlue)
            ],
            providerID: .cursor,
            modelId: AvailableModels.autoID,
            taskState: .inProgress
        )

        let store = TasksListStore()
        store.configure(workspacePath: workspacePath, linkedStatuses: [:])
        store.editingTask = originalTask
        store.editingDraft = "Edited"

        store.commitEdit(screenshotData: [try makeTestPNGData(color: .systemGreen)])

        guard let updatedTask = ProjectTasksStorage.task(workspacePath: workspacePath, id: originalTask.id) else {
            XCTFail("Expected edited task to exist")
            return
        }

        XCTAssertEqual(updatedTask.content, "Edited")
        XCTAssertEqual(updatedTask.screenshotPaths.count, 1)

        let remainingURL = ProjectTasksStorage.taskScreenshotFileURL(
            workspacePath: workspacePath,
            screenshotPath: updatedTask.screenshotPaths[0]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: remainingURL.path))

        let removedURL = ProjectTasksStorage.taskScreenshotFileURL(
            workspacePath: workspacePath,
            screenshotPath: "screenshots/\(originalTask.id.uuidString)_1.png"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
    }
}
