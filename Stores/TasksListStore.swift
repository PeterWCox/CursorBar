import Foundation
import AppKit
import Combine

enum TasksListTab: String, CaseIterable {
    case backlog = "Backlog"
    case inProgress = "In Progress"
    case completed = "Completed"
    case deleted = "Deleted"
}

struct SectionScopedTaskRow: Identifiable, Equatable {
    let sectionID: String
    let task: ProjectTask

    var id: String {
        "\(sectionID)-\(task.id.uuidString)"
    }
}

struct TasksTabCounts: Equatable {
    let backlog: Int
    let inProgress: Int
    let completed: Int
    let deleted: Int

    func count(for tab: TasksListTab) -> Int {
        switch tab {
        case .backlog: return backlog
        case .inProgress: return inProgress
        case .completed: return completed
        case .deleted: return deleted
        }
    }
}

struct TimeBucketGroup: Identifiable, Equatable {
    let title: String
    let tasks: [ProjectTask]

    var id: String { title }
}

enum TimeBucket: Int, CaseIterable {
    case today = 0
    case yesterday = 1
    case last7Days = 2
    case last30Days = 3
    case older = 4

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .older: return "Older"
        }
    }

    static func bucket(for date: Date, reference: Date = Date(), calendar: Calendar = .current) -> TimeBucket {
        let startOfToday = calendar.startOfDay(for: reference)
        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday) else {
            return .older
        }
        if date >= startOfToday { return .today }
        if date >= startOfYesterday { return .yesterday }
        if date >= sevenDaysAgo { return .last7Days }
        if date >= thirtyDaysAgo { return .last30Days }
        return .older
    }
}

struct TasksListSnapshot: Equatable {
    let backlogTasks: [ProjectTask]
    let reviewRows: [SectionScopedTaskRow]
    let stoppedRows: [SectionScopedTaskRow]
    let processingRows: [SectionScopedTaskRow]
    let todoRows: [SectionScopedTaskRow]
    let visibleCompletedTasks: [ProjectTask]
    let completedGrouped: [TimeBucketGroup]
    let deletedTasks: [ProjectTask]
    let deletedGrouped: [TimeBucketGroup]
    let counts: TasksTabCounts

    static let empty = TasksListSnapshot(
        backlogTasks: [],
        reviewRows: [],
        stoppedRows: [],
        processingRows: [],
        todoRows: [],
        visibleCompletedTasks: [],
        completedGrouped: [],
        deletedTasks: [],
        deletedGrouped: [],
        counts: TasksTabCounts(backlog: 0, inProgress: 0, completed: 0, deleted: 0)
    )
}

@MainActor
final class TasksListStore: ObservableObject {
    private static let completedRecentInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var workspacePath: String = ""
    @Published private(set) var snapshot: TasksListSnapshot = .empty
    @Published private(set) var debugURL: String = ""
    @Published private(set) var startupScripts: [String] = []

    @Published var editingTask: ProjectTask?
    @Published var editingDraft: String = ""
    @Published var isAddingNewTask: Bool = false
    @Published var newTaskDraft: String = ""
    @Published var newTaskModelId: String = AvailableModels.autoID
    @Published var showOnlyRecentCompleted: Bool = true
    @Published var expandedCompletedSections: Set<String> = ["Today"]
    @Published var expandedDeletedSections: Set<String> = ["Today"]
    @Published var selectedTasksTab: TasksListTab = .inProgress
    @Published var previewRunningInExternalTerminal: Bool = false

    private var tasks: [ProjectTask] = []
    private var deletedTasksList: [ProjectTask] = []
    private var linkedStatuses: [UUID: AgentTaskState] = [:]
    private var tasksObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    init() {
        tasksObserver = NotificationCenter.default.addObserver(
            forName: ProjectTasksStorage.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let changedWorkspace = notification.userInfo?["workspacePath"] as? String,
                  changedWorkspace == self.workspacePath else { return }
            self.reload()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: ProjectSettingsStorage.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let changedWorkspace = notification.userInfo?["workspacePath"] as? String,
                  changedWorkspace == self.workspacePath else { return }
            self.reloadSettings()
        }
    }

    deinit {
        if let tasksObserver {
            NotificationCenter.default.removeObserver(tasksObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    func configure(workspacePath: String, linkedStatuses: [UUID: AgentTaskState]) {
        let normalizedPath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceChanged = self.workspacePath != normalizedPath
        self.workspacePath = normalizedPath
        self.linkedStatuses = linkedStatuses
        if workspaceChanged {
            resetTransientStateForNewWorkspace()
        }
        reload()
    }

    func updateLinkedStatuses(_ linkedStatuses: [UUID: AgentTaskState]) {
        self.linkedStatuses = linkedStatuses
        recomputeSnapshot()
    }

    func reload() {
        guard !workspacePath.isEmpty else { return }
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
        deletedTasksList = ProjectTasksStorage.deletedTasks(workspacePath: workspacePath)
        reloadSettings()
        recomputeSnapshot()
    }

    func reloadSettings() {
        guard !workspacePath.isEmpty else { return }
        debugURL = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) ?? ""
        startupScripts = ProjectSettingsStorage.getStartupScripts(workspacePath: workspacePath)
    }

    func setShowOnlyRecentCompleted(_ enabled: Bool) {
        guard showOnlyRecentCompleted != enabled else { return }
        showOnlyRecentCompleted = enabled
        recomputeSnapshot()
    }

    func setCompletedSectionExpanded(_ title: String, expanded: Bool) {
        if expanded {
            expandedCompletedSections.insert(title)
        } else {
            expandedCompletedSections.remove(title)
        }
    }

    func setDeletedSectionExpanded(_ title: String, expanded: Bool) {
        if expanded {
            expandedDeletedSections.insert(title)
        } else {
            expandedDeletedSections.remove(title)
        }
    }

    func commitNewTask(screenshotImages: [NSImage], providerID: AgentProviderID) {
        let trimmed = newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !workspacePath.isEmpty else { return }
        recordHangEvent("tasks-commit-new-task", metadata: [
            "contentLength": "\(trimmed.count)",
            "screenshots": "\(screenshotImages.count)"
        ])

        let taskState: TaskState = (selectedTasksTab == .backlog) ? .backlog : .inProgress
        _ = ProjectTasksStorage.addTask(
            workspacePath: workspacePath,
            content: trimmed,
            screenshotImages: screenshotImages,
            providerID: providerID,
            modelId: newTaskModelId,
            taskState: taskState
        )

        reload()
        newTaskDraft = ""
        newTaskModelId = AvailableModels.autoID
        isAddingNewTask = false
    }

    func cancelNewTask() {
        recordHangEvent("tasks-cancel-new-task")
        newTaskDraft = ""
        newTaskModelId = AvailableModels.autoID
        isAddingNewTask = false
    }

    func showNewTaskComposer(selecting tab: TasksListTab? = nil) {
        if let tab {
            selectedTasksTab = tab
        }
        newTaskDraft = ""
        newTaskModelId = AvailableModels.autoID
        isAddingNewTask = true
    }

    func selectTasksTab(_ tab: TasksListTab) {
        guard selectedTasksTab != tab else { return }
        recordHangEvent("tasks-select-tab", metadata: [
            "from": selectedTasksTab.rawValue,
            "to": tab.rawValue
        ])
        if tab != .inProgress && tab != .backlog && isAddingNewTask {
            cancelNewTask()
        }
        selectedTasksTab = tab
    }

    func commitEdit(screenshotImages: [NSImage]) {
        let trimmed = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let id = editingTask?.id, !workspacePath.isEmpty {
            ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: id, content: trimmed)
            ProjectTasksStorage.updateTaskScreenshots(workspacePath: workspacePath, id: id, images: screenshotImages)
            reload()
        }
        editingTask = nil
    }

    func toggleTaskCompletion(_ task: ProjectTask) {
        let nextState: TaskState = (task.taskState == .completed) ? .inProgress : .completed
        ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: nextState)
        reload()
    }

    func updateTaskModel(_ task: ProjectTask, modelId: String) {
        ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, modelId: modelId)
        reload()
    }

    func moveTask(_ task: ProjectTask, to state: TaskState) {
        ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: state)
        reload()
    }

    func deleteTask(_ task: ProjectTask) {
        ProjectTasksStorage.deleteTask(workspacePath: workspacePath, id: task.id)
        reload()
    }

    func restoreTask(_ task: ProjectTask) {
        ProjectTasksStorage.restoreTask(workspacePath: workspacePath, id: task.id)
        reload()
    }

    func permanentlyDeleteTask(_ task: ProjectTask) {
        ProjectTasksStorage.permanentlyDeleteTask(workspacePath: workspacePath, id: task.id)
        reload()
    }

    func removeTaskScreenshot(taskID: UUID, screenshotPath: String) {
        ProjectTasksStorage.removeTaskScreenshot(workspacePath: workspacePath, id: taskID, screenshotPath: screenshotPath)
        reload()
    }

    private func resetTransientStateForNewWorkspace() {
        editingTask = nil
        editingDraft = ""
        isAddingNewTask = false
        newTaskDraft = ""
        newTaskModelId = AvailableModels.autoID
        previewRunningInExternalTerminal = false
        showOnlyRecentCompleted = true
        expandedCompletedSections = ["Today"]
        expandedDeletedSections = ["Today"]
        selectedTasksTab = .inProgress
    }

    private func recomputeSnapshot(referenceDate: Date = Date()) {
        let backlogTasks = tasks.filter { $0.taskState == .backlog }
        let inProgressTasks = tasks.filter { $0.taskState == .inProgress }
        let completedTasks = tasks.filter { $0.taskState == .completed }
        let reviewTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .review }
        let stoppedTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .stopped }
        let processingTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .processing }
        let todoTasks = inProgressTasks.filter {
            let state = linkedStatuses[$0.id]
            return state == nil || state == .none || state == .todo
        }

        let cutoff = referenceDate.addingTimeInterval(-Self.completedRecentInterval)
        let visibleCompletedTasks = showOnlyRecentCompleted
            ? completedTasks.filter { ($0.completedAt ?? .distantPast) >= cutoff }
            : completedTasks
        let sortedVisibleCompletedTasks = visibleCompletedTasks
            .sorted { ($0.completedAt ?? .distantPast) >= ($1.completedAt ?? .distantPast) }

        snapshot = TasksListSnapshot(
            backlogTasks: backlogTasks,
            reviewRows: reviewTasks.map { SectionScopedTaskRow(sectionID: "Review", task: $0) },
            stoppedRows: stoppedTasks.map { SectionScopedTaskRow(sectionID: "Stopped", task: $0) },
            processingRows: processingTasks.map { SectionScopedTaskRow(sectionID: "Processing", task: $0) },
            todoRows: todoTasks.map { SectionScopedTaskRow(sectionID: "Todo", task: $0) },
            visibleCompletedTasks: sortedVisibleCompletedTasks,
            completedGrouped: Self.groupTasksByTimeBucket(
                sortedVisibleCompletedTasks,
                dateKeyPath: \.completedAt,
                reference: referenceDate
            ),
            deletedTasks: deletedTasksList,
            deletedGrouped: Self.groupTasksByTimeBucket(
                deletedTasksList,
                dateKeyPath: \.deletedAt,
                reference: referenceDate
            ),
            counts: TasksTabCounts(
                backlog: backlogTasks.count,
                inProgress: inProgressTasks.count,
                completed: completedTasks.count,
                deleted: deletedTasksList.count
            )
        )

        updateHangDiagnosticsSnapshot()
    }

    private static func groupTasksByTimeBucket(
        _ tasks: [ProjectTask],
        dateKeyPath: KeyPath<ProjectTask, Date?>,
        reference: Date
    ) -> [TimeBucketGroup] {
        let calendar = Calendar.current
        var buckets: [TimeBucket: [ProjectTask]] = [:]
        for task in tasks {
            let date = task[keyPath: dateKeyPath] ?? .distantPast
            let bucket = TimeBucket.bucket(for: date, reference: reference, calendar: calendar)
            buckets[bucket, default: []].append(task)
        }
        return TimeBucket.allCases
            .filter { (buckets[$0]?.count ?? 0) > 0 }
            .map { TimeBucketGroup(title: $0.title, tasks: buckets[$0] ?? []) }
    }

    private func updateHangDiagnosticsSnapshot() {
        HangDiagnostics.shared.updateSnapshot(hangDiagnosticsSnapshot())
    }

    private func recordHangEvent(_ event: String, metadata: [String: String] = [:]) {
        updateHangDiagnosticsSnapshot()
        HangDiagnostics.shared.record(event, metadata: metadata)
    }

    private func hangDiagnosticsSnapshot() -> [String: String] {
        [
            "tasksWorkspacePath": workspacePath,
            "tasksSelectedTab": selectedTasksTab.rawValue,
            "tasksBacklogCount": "\(snapshot.counts.backlog)",
            "tasksInProgressCount": "\(snapshot.counts.inProgress)",
            "tasksProcessingCount": "\(snapshot.processingRows.count)",
            "tasksReviewCount": "\(snapshot.reviewRows.count)",
            "tasksStoppedCount": "\(snapshot.stoppedRows.count)",
            "tasksTodoCount": "\(snapshot.todoRows.count)",
            "tasksCompletedCount": "\(snapshot.counts.completed)",
            "tasksDeletedCount": "\(snapshot.counts.deleted)",
            "tasksIsAddingNew": isAddingNewTask ? "true" : "false"
        ]
    }
}
