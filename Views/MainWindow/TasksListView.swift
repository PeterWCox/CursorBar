import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tasks (todos) list for a project

/// One tab per task state.
enum TasksListTab: String, CaseIterable {
    case backlog = "Backlog"
    case inProgress = "In Progress"
    case completed = "Completed"
    case deleted = "Deleted"
}

private struct SectionScopedTaskRow: Identifiable {
    let sectionID: String
    let task: ProjectTask

    var id: String {
        "\(sectionID)-\(task.id.uuidString)"
    }
}

struct TasksListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    /// When set to true from outside (e.g. Cmd+T), show the add-new-task row and focus it.
    var triggerAddNewTask: Binding<Bool> = .constant(false)
    /// Linked agent status per task ID so the task row can show review/processing state separately from task lifecycle.
    var linkedStatuses: [UUID: AgentTaskState] = [:]
    /// Models to show in the task model picker (same as input bar).
    var models: [ModelOption]
    /// Send task content to a new agent; when taskID is non-nil, the new agent is linked to that task. When screenshotPaths is non-empty, those paths (under .metro) are attached to the prompt. modelId is the task's chosen model (e.g. "auto").
    var onSendToAgent: (String, UUID?, [String], String) -> Void
    /// Open the linked agent for a task when the row represents active or completed agent work.
    var onOpenLinkedAgent: (ProjectTask) -> Void = { _ in }
    /// Continue a stopped agent: focus its tab and send the "continue" prompt.
    var onContinueAgent: (ProjectTask) -> Void = { _ in }
    /// Stop the agent currently running for a task (from the Processing section).
    var onStopAgent: (ProjectTask) -> Void = { _ in }
    /// Called when any task is updated (e.g. completed, edited) so the sidebar can refresh (e.g. hide agent tabs for completed tasks).
    var onTasksDidUpdate: () -> Void = { }
    var onDismiss: () -> Void

    @State private var tasks: [ProjectTask] = []
    @State private var editingTask: ProjectTask?
    @State private var editingDraft: String = ""
    @State private var isAddingNewTask: Bool = false
    @State private var newTaskDraft: String = ""
    @State private var newTaskModelId: String = AvailableModels.autoID
    @FocusState private var isNewTaskFieldFocused: Bool
    @FocusState private var isTaskEditorFocused: Bool
    /// When true, show only completed tasks completed in the last 24 hours. When false, show all completed.
    @State private var showOnlyRecentCompleted: Bool = true
    @State private var deletedTasksList: [ProjectTask] = []
    /// URL for full-screen task screenshot preview (saved task screenshots). Same pattern as PopoutView.
    @State private var taskScreenshotPreviewURL: URL? = nil
    /// In-memory image for full-screen preview (new-task draft screenshots before save).
    @State private var taskScreenshotPreviewImage: NSImage? = nil
    /// Draft screenshots for the new task row (paste before commit). Shown with same thumbnail + preview as existing tasks.
    @State private var newTaskDraftScreenshots: [(id: UUID, image: NSImage)] = []
    /// While the add-task row is visible, intercept Cmd+V for image paste without breaking normal text paste.
    @State private var newTaskPasteKeyMonitor: Any?
    /// Which top-level tab is selected.
    @State private var selectedTasksTab: TasksListTab = .inProgress
    @State private var isNewTaskButtonHovered: Bool = false

    private static let completedRecentInterval: TimeInterval = 24 * 60 * 60

    private func reloadTasks() {
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
        deletedTasksList = ProjectTasksStorage.deletedTasks(workspacePath: workspacePath)
    }

    private var backlogTasks: [ProjectTask] {
        tasks.filter { $0.taskState == .backlog }
    }

    private var inProgressTasks: [ProjectTask] {
        tasks.filter { $0.taskState == .inProgress }
    }

    private var reviewTasks: [ProjectTask] {
        inProgressTasks.filter { linkedStatuses[$0.id] == .review }
    }

    private var stoppedTasks: [ProjectTask] {
        inProgressTasks.filter { linkedStatuses[$0.id] == .stopped }
    }

    private var processingTasks: [ProjectTask] {
        inProgressTasks.filter { linkedStatuses[$0.id] == .processing }
    }

    private var todoTasks: [ProjectTask] {
        inProgressTasks.filter {
            let state = linkedStatuses[$0.id]
            return state == nil || state == AgentTaskState.none || state == .todo
        }
    }

    private var completedTasks: [ProjectTask] {
        tasks.filter { $0.taskState == .completed }
    }

    private var visibleCompletedTasks: [ProjectTask] {
        let cutoff = Date().addingTimeInterval(-Self.completedRecentInterval)
        let filtered = showOnlyRecentCompleted
            ? completedTasks.filter { ($0.completedAt ?? .distantPast) >= cutoff }
            : completedTasks
        return filtered.sorted { ($0.completedAt ?? .distantPast) >= ($1.completedAt ?? .distantPast) }
    }

    private func commitNewTask() {
        let trimmed = newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let taskState: TaskState = (selectedTasksTab == .backlog) ? .backlog : .inProgress
            _ = ProjectTasksStorage.addTask(
                workspacePath: workspacePath,
                content: trimmed,
                screenshotImages: newTaskDraftScreenshots.map(\.image),
                modelId: newTaskModelId,
                taskState: taskState
            )
            reloadTasks()
            newTaskDraft = ""
            newTaskDraftScreenshots = []
            newTaskModelId = AvailableModels.autoID
        }
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    private func cancelNewTask() {
        newTaskDraft = ""
        newTaskDraftScreenshots = []
        taskScreenshotPreviewImage = nil
        newTaskModelId = AvailableModels.autoID
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    private func installNewTaskPasteMonitorIfNeeded() {
        guard newTaskPasteKeyMonitor == nil else { return }
        newTaskPasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCommandV = modifiers.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isCommandV else { return event }
            guard newTaskDraftScreenshots.count < AppLimits.maxScreenshots else { return event }
            guard let image = SubmittableTextEditor.imageFromPasteboard(.general) else { return event }
            newTaskDraftScreenshots.append((id: UUID(), image: image))
            return nil
        }
    }

    private func removeNewTaskPasteMonitor() {
        guard let monitor = newTaskPasteKeyMonitor else { return }
        NSEvent.removeMonitor(monitor)
        newTaskPasteKeyMonitor = nil
    }

    private func showNewTaskComposer(selecting tab: TasksListTab? = nil) {
        if let tab {
            selectedTasksTab = tab
        }
        newTaskDraft = ""
        newTaskDraftScreenshots = []
        taskScreenshotPreviewImage = nil
        newTaskModelId = AvailableModels.autoID
        isAddingNewTask = true
    }

    private func selectTasksTab(_ tab: TasksListTab) {
        guard selectedTasksTab != tab else { return }
        if tab != .inProgress && tab != .backlog && isAddingNewTask {
            cancelNewTask()
        }
        selectedTasksTab = tab
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tasksTabBar
            Divider()
                .background(CursorTheme.border(for: colorScheme))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: CursorTheme.spacingListItems) {
                        Color.clear
                            .frame(height: 0)
                            .id("tasksScrollTop")
                        tabContent()
                    }
                    .padding(CursorTheme.paddingPanel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: isAddingNewTask) { _, showing in
                    if showing {
                        proxy.scrollTo("tasksScrollTop", anchor: .top)
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadTasks()
            // Handle Cmd+T when it fired before this view was in the hierarchy (trigger already true).
            if triggerAddNewTask.wrappedValue {
                showNewTaskComposer(selecting: .inProgress)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: workspacePath) { _, _ in reloadTasks() }
        .onChange(of: triggerAddNewTask.wrappedValue) { _, requested in
            if requested {
                showNewTaskComposer(selecting: .inProgress)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: isAddingNewTask) { _, showing in
            if showing {
                isNewTaskFieldFocused = true
                installNewTaskPasteMonitorIfNeeded()
            } else {
                removeNewTaskPasteMonitor()
            }
        }
        .onDisappear { removeNewTaskPasteMonitor() }
        .overlay {
            if taskScreenshotPreviewURL != nil || taskScreenshotPreviewImage != nil {
                ScreenshotPreviewModal(
                    imageURL: taskScreenshotPreviewURL,
                    image: taskScreenshotPreviewImage,
                    isPresented: Binding(
                        get: { true },
                        set: { if !$0 { taskScreenshotPreviewURL = nil; taskScreenshotPreviewImage = nil } }
                    )
                )
            }
        }
    }

    private func taskCount(for tab: TasksListTab) -> Int {
        switch tab {
        case .backlog: return backlogTasks.count
        case .inProgress: return inProgressTasks.count
        case .completed: return completedTasks.count
        case .deleted: return deletedTasksList.count
        }
    }

    private var tasksTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TasksListTab.allCases, id: \.self) { tab in
                Button {
                    selectTasksTab(tab)
                } label: {
                    Text("\(tab.rawValue) (\(taskCount(for: tab)))")
                        .font(.system(size: 13, weight: selectedTasksTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTasksTab == tab ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, CursorTheme.spaceM)
                        .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
                }
                .buttonStyle(.plain)
                .background(selectedTasksTab == tab ? CursorTheme.surfaceMuted(for: colorScheme) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.spaceXS)
        .background(CursorTheme.chrome(for: colorScheme))
    }

    @ViewBuilder
    private func tabContent() -> some View {
        switch selectedTasksTab {
        case .inProgress:
            inProgressContent
        case .backlog:
            backlogContent
        case .completed:
            completedContent
        case .deleted:
            deletedContent
        }
    }

    @ViewBuilder
    private var inProgressContent: some View {
        newTaskButton
        let isEmpty = inProgressTasks.isEmpty && !isAddingNewTask
        if isEmpty {
            emptyStateInProgress
        } else {
            if isAddingNewTask {
                newTaskRow
            }
            inProgressSection(title: "Review", tasks: reviewTasks)
            inProgressSection(title: "Stopped", tasks: stoppedTasks)
            inProgressSection(title: "Processing", tasks: processingTasks)
            inProgressSection(title: "Todo", tasks: todoTasks)
        }
    }

    @ViewBuilder
    private func inProgressSection(title: String, tasks sectionTasks: [ProjectTask]) -> some View {
        if !sectionTasks.isEmpty {
            let scopedTasks = sectionTasks.map { SectionScopedTaskRow(sectionID: title, task: $0) }
            VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                HStack(spacing: CursorTheme.spaceXS) {
                    sectionStatusIcon(title: title)
                    Text(title)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                        .foregroundStyle(
                            title == "Review" ? CursorTheme.semanticReview
                            : title == "Stopped" ? CursorTheme.semanticError
                            : CursorTheme.textSecondary(for: colorScheme)
                        )
                }
                ForEach(scopedTasks) { item in
                    let task = item.task
                    let canMoveToBacklog = linkedStatuses[task.id] == nil || linkedStatuses[task.id] == AgentTaskState.none
                    taskRow(
                        task,
                        stateTransitionLabel: canMoveToBacklog ? "Move to Backlog" : nil,
                        stateTransitionIcon: "tray.full",
                        onStateTransition: canMoveToBacklog ? {
                            ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: .backlog)
                            reloadTasks()
                        } : nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sectionStatusIcon(title: String) -> some View {
        Group {
            switch title {
            case "Review":
                Image(systemName: "clock.fill")
                    .font(.system(size: CursorTheme.fontIconList))
                    .foregroundStyle(CursorTheme.semanticReview)
            case "Stopped":
                Image(systemName: "square.fill")
                    .font(.system(size: CursorTheme.fontIconList, weight: .semibold))
                    .foregroundStyle(CursorTheme.semanticError)
            case "Processing":
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: CursorTheme.fontIconList))
                    .foregroundStyle(CursorTheme.spinnerBlue)
            case "Todo":
                Image(systemName: "person")
                    .font(.system(size: CursorTheme.fontIconList - 2, weight: .medium))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            default:
                Image(systemName: "circle")
                    .font(.system(size: CursorTheme.fontIconList))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            }
        }
    }

    private var newTaskButton: some View {
        Button(action: {
            showNewTaskComposer()
        }) {
            Label("New task", systemImage: "plus.circle.fill")
                .font(.system(size: CursorTheme.fontBody, weight: .medium))
                .foregroundStyle(CursorTheme.brandBlue)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CursorTheme.spaceS)
        .onHover { isNewTaskButtonHovered = $0 }
        .overlay(alignment: .top) {
            if isNewTaskButtonHovered {
                Text("⌘T")
                    .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .padding(.horizontal, CursorTheme.paddingBadgeHorizontal)
                    .padding(.vertical, CursorTheme.paddingBadgeVertical)
                    .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.spaceXS))
                    .overlay(RoundedRectangle(cornerRadius: CursorTheme.spaceXS).strokeBorder(CursorTheme.border(for: colorScheme), lineWidth: 1))
                    .offset(y: -32)
                    .padding(.top, CursorTheme.spaceS)
            }
        }
    }

    @ViewBuilder
    private var backlogContent: some View {
        newTaskButton
        let isEmpty = backlogTasks.isEmpty && !isAddingNewTask
        if isEmpty {
            emptyStateBacklog
        } else {
            if isAddingNewTask {
                newTaskRow
            }
            ForEach(backlogTasks) { task in
                taskRow(task, stateTransitionLabel: "Move to In Progress", stateTransitionIcon: "arrow.right.circle", onStateTransition: {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: .inProgress)
                    reloadTasks()
                })
            }
        }
    }

    @ViewBuilder
    private var completedContent: some View {
        if visibleCompletedTasks.isEmpty {
            emptyStateCompleted
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: { showOnlyRecentCompleted.toggle() }) {
                    Text(showOnlyRecentCompleted ? "Show all" : "Last 24 hours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.brandBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, CursorTheme.spaceXS)
            ForEach(visibleCompletedTasks) { task in
                taskRow(task)
            }
        }
    }

    @ViewBuilder
    private var deletedContent: some View {
        if deletedTasksList.isEmpty {
            emptyStateDeleted
        } else {
            ForEach(deletedTasksList) { task in
                deletedTaskRow(task)
            }
        }
    }

    private func commitEdit() {
        let trimmed = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let id = editingTask?.id {
            ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: id, content: trimmed)
            reloadTasks()
        }
        editingTask = nil
    }

    @ViewBuilder
    private func taskRow(
        _ task: ProjectTask,
        stateTransitionLabel: String? = nil,
        stateTransitionIcon: String = "arrow.right.circle",
        onStateTransition: (() -> Void)? = nil
    ) -> some View {
        TaskRowView(
            task: task,
            workspacePath: workspacePath,
            models: models,
            agentTaskState: linkedStatuses[task.id] ?? .none,
            isEditing: editingTask?.id == task.id,
            editDraft: $editingDraft,
            isEditorFocused: $isTaskEditorFocused,
            onTap: {
                if let linkedState = linkedStatuses[task.id], linkedState != AgentTaskState.none {
                    onOpenLinkedAgent(task)
                } else {
                    let content = task.content
                    let taskToEdit = task
                    // Defer so when triggered from context/menu the menu dismisses first and inline editor gets focus
                    DispatchQueue.main.async {
                        editingDraft = content
                        editingTask = taskToEdit
                    }
                }
            },
            onCommitEdit: commitEdit,
            onCancelEdit: { editingTask = nil },
            onToggleComplete: {
                let nextState: TaskState = (task.taskState == .completed) ? .inProgress : .completed
                ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: nextState)
                reloadTasks()
                onTasksDidUpdate()
            },
            onSendToAgent: { onSendToAgent(task.content, task.id, task.screenshotPaths, task.modelId) },
            onModelChange: { newId in
                ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, modelId: newId)
                reloadTasks()
            },
            onDelete: {
                ProjectTasksStorage.deleteTask(workspacePath: workspacePath, id: task.id)
                reloadTasks()
            },
            onPreviewScreenshot: { path in
                taskScreenshotPreviewURL = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            },
            onDeleteScreenshot: !task.completed ? { path in
                ProjectTasksStorage.removeTaskScreenshot(workspacePath: workspacePath, id: task.id, screenshotPath: path)
                reloadTasks()
            } : nil,
            stateTransitionLabel: stateTransitionLabel,
            stateTransitionIcon: stateTransitionIcon,
            onStateTransition: onStateTransition,
            onStopAgent: linkedStatuses[task.id] == .processing ? { onStopAgent(task) } : nil,
            onContinueAgent: linkedStatuses[task.id] == .stopped ? { onContinueAgent(task) } : nil
        )
    }

    @ViewBuilder
    private func deletedTaskRow(_ task: ProjectTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
            VStack(alignment: .leading, spacing: 4) {
                Text(task.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .strikethrough()
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    ProjectTasksStorage.restoreTask(workspacePath: workspacePath, id: task.id)
                    reloadTasks()
                }
                Divider()
                Button("Delete permanently", systemImage: "trash", role: .destructive) {
                    ProjectTasksStorage.permanentlyDeleteTask(workspacePath: workspacePath, id: task.id)
                    reloadTasks()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .contextMenu {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                ProjectTasksStorage.restoreTask(workspacePath: workspacePath, id: task.id)
                reloadTasks()
            }
            Divider()
            Button("Delete permanently", systemImage: "trash", role: .destructive) {
                ProjectTasksStorage.permanentlyDeleteTask(workspacePath: workspacePath, id: task.id)
                reloadTasks()
            }
        }
    }

    private var header: some View {
        HStack(spacing: CursorTheme.spaceM) {
            Button(action: onDismiss) {
                Image(systemName: "checklist")
                    .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                HStack(spacing: CursorTheme.spaceXS) {
                    Image(systemName: "folder")
                        .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    Text((workspacePath as NSString).lastPathComponent)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.paddingHeaderVertical)
    }

    private var emptyStateBacklog: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.full")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text("No backlog tasks")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            Text("Create tasks here when you want to queue them up before moving them into active work.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CursorTheme.spaceXXL + CursorTheme.spaceL)
    }

    private var emptyStateCompleted: some View {
        emptyStatePlaceholder(
            icon: "checkmark.circle.fill",
            title: "No completed tasks",
            subtitle: "Tasks you mark as done appear here."
        )
    }

    private var emptyStateDeleted: some View {
        emptyStatePlaceholder(
            icon: "trash",
            title: "No deleted tasks",
            subtitle: "Deleted tasks appear here until you restore or permanently remove them."
        )
    }

    private var emptyStateInProgress: some View {
        emptyStatePlaceholder(
            icon: "checklist",
            title: "No in-progress tasks",
            subtitle: "Move a backlog task here or create a new task to start active work."
        )
    }

    private func emptyStatePlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CursorTheme.spaceXXL + CursorTheme.spaceL)
    }

    private var newTaskRow: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceS + CursorTheme.spaceXXS) {
            HStack(alignment: .top, spacing: CursorTheme.spaceS + CursorTheme.spaceXXS) {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $newTaskDraft)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .focused($isNewTaskFieldFocused)
                        .onKeyPress { press in
                            if press.key == .return && !NSEvent.modifierFlags.contains(.shift) {
                                commitNewTask()
                                return .handled
                            }
                            return .ignored
                        }
                        .onKeyPress(.escape) {
                            cancelNewTask()
                            return .handled
                        }
                        .frame(minHeight: 24, maxHeight: 120)
                        .padding(.horizontal, -4)
                        .padding(.vertical, -4)
                    if newTaskDraft.isEmpty {
                        Text("New task…")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            .allowsHitTesting(false)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)

                Button(action: cancelNewTask) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }

            if !newTaskDraftScreenshots.isEmpty {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(newTaskDraftScreenshots, id: \.id) { item in
                        ScreenshotThumbnailView(
                            image: item.image,
                            size: CGSize(width: 56, height: 56),
                            cornerRadius: 6,
                            onTapPreview: { taskScreenshotPreviewImage = item.image },
                            onDelete: {
                                if taskScreenshotPreviewImage === item.image { taskScreenshotPreviewImage = nil }
                                newTaskDraftScreenshots.removeAll { $0.id == item.id }
                            }
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: CursorTheme.spaceS + CursorTheme.spaceXXS) {
                ModelPickerView(
                    selectedModelId: newTaskModelId,
                    models: models,
                    onSelect: { newTaskModelId = $0 }
                )
            }
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .onPasteCommand(of: [.image, .png, .tiff]) { providers in
            guard newTaskDraftScreenshots.count < AppLimits.maxScreenshots else { return }
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let img = object as? NSImage else { return }
                    DispatchQueue.main.async {
                        if newTaskDraftScreenshots.count < AppLimits.maxScreenshots {
                            newTaskDraftScreenshots.append((id: UUID(), image: img))
                        }
                    }
                }
                break
            }
        }
    }

}

// MARK: - Task screenshot thumbnail (in todo row): uses shared ScreenshotThumbnailView

private struct TaskScreenshotThumbnailView: View {
    let workspacePath: String
    let screenshotPath: String
    var size: CGSize = CGSize(width: 56, height: 56)
    var onTapPreview: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var imageURL: URL {
        ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
    }

    var body: some View {
        ScreenshotThumbnailView(
            imageURL: imageURL,
            size: size,
            cornerRadius: 6,
            onTapPreview: onTapPreview,
            onDelete: onDelete
        )
    }
}

// MARK: - Inline screenshot strip: single thumb or pile + pill; prev/next when focused

private struct TaskScreenshotStripView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    let paths: [String]
    var onPreview: (String) -> Void = { _ in }
    var onDelete: ((String) -> Void)? = nil

    private static let thumbSize: CGSize = CGSize(width: 36, height: 36)
    @State private var selectedIndex: Int = 0
    @State private var isHovered: Bool = false

    private var currentPath: String? {
        guard !paths.isEmpty, paths.indices.contains(selectedIndex) else { return nil }
        return paths[selectedIndex]
    }

    @ViewBuilder
    var body: some View {
        if paths.isEmpty {
            EmptyView()
        } else if paths.count == 1, let path = paths.first {
            TaskScreenshotThumbnailView(
                workspacePath: workspacePath,
                screenshotPath: path,
                size: Self.thumbSize,
                onTapPreview: { onPreview(path) },
                onDelete: onDelete.map { cb in { cb(path) } }
            )
        } else {
            // Multiple: pile + pill, prev/next when hovered
            HStack(spacing: 2) {
                if isHovered {
                    Button {
                        selectedIndex = (selectedIndex - 1 + paths.count) % paths.count
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            .frame(width: 20, height: Self.thumbSize.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ZStack(alignment: .bottomTrailing) {
                    if let path = currentPath {
                        TaskScreenshotThumbnailView(
                            workspacePath: workspacePath,
                            screenshotPath: path,
                            size: Self.thumbSize,
                            onTapPreview: { onPreview(path) },
                            onDelete: nil
                        )
                    }
                    Text("\(paths.count)")
                        .font(.system(size: CursorTheme.fontTiny, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .padding(.horizontal, CursorTheme.paddingBadgeHorizontal)
                        .padding(.vertical, CursorTheme.paddingBadgeVertical)
                        .background(CursorTheme.surfaceRaised(for: colorScheme), in: Capsule())
                        .overlay(Capsule().strokeBorder(CursorTheme.border(for: colorScheme), lineWidth: 1))
                        .offset(x: 4, y: 4)
                }
                .onTapGesture { if let p = currentPath { onPreview(p) } }
                if isHovered {
                    Button {
                        selectedIndex = (selectedIndex + 1) % paths.count
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                            .frame(width: 20, height: Self.thumbSize.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: ProjectTask
    let workspacePath: String
    var models: [ModelOption] = []
    /// Agent state is independent from the task lifecycle and drives the In Progress grouping.
    var agentTaskState: AgentTaskState = .none
    var isEditing: Bool = false
    @Binding var editDraft: String
    var isEditorFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onToggleComplete: () -> Void
    let onSendToAgent: () -> Void
    var onModelChange: ((String) -> Void)? = nil
    let onDelete: () -> Void
    var onPreviewScreenshot: ((String) -> Void)? = nil
    var onDeleteScreenshot: ((String) -> Void)? = nil
    var stateTransitionLabel: String? = nil
    var stateTransitionIcon: String = "arrow.right.circle"
    var onStateTransition: (() -> Void)? = nil
    /// When non-nil (processing tasks), the row shows a 3-dot menu with a single "Stop agent" item.
    var onStopAgent: (() -> Void)? = nil
    /// When non-nil (stopped tasks), the row shows "Continue" which focuses the agent and sends "continue".
    var onContinueAgent: (() -> Void)? = nil

    private var isProcessing: Bool { agentTaskState == .processing }
    private var isStopped: Bool { agentTaskState == .stopped }
    private var canOpenLinkedAgent: Bool { agentTaskState != .none }
    private var canDelegate: Bool { task.taskState == .inProgress && agentTaskState == .none }
    /// Stopped agents are not editable; only non-completed, non-processing, non-stopped tasks can be edited.
    private var canEdit: Bool { !task.completed && !isProcessing && !isStopped }

    var body: some View {
        HStack(alignment: .top, spacing: CursorTheme.spaceS) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                if isEditing && !task.completed {
                    TextEditor(text: $editDraft)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .scrollContentBackground(.hidden)
                        .lineSpacing(6)
                        .padding(.vertical, CursorTheme.spaceXS)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 36, maxHeight: 160)
                        .focused(isEditorFocused)
                        .onKeyPress { press in
                            if press.key == .return {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    return .ignored
                                }
                                onCommitEdit()
                                return .handled
                            }
                            return .ignored
                        }
                        .onKeyPress(.escape) {
                            onCancelEdit()
                            return .handled
                        }
                    if !models.isEmpty {
                        ModelPickerView(
                            selectedModelId: task.modelId,
                            models: models,
                            onSelect: { onModelChange?($0) }
                        )
                        .disabled(isProcessing)
                    }
                } else {
                    // Same line: task text | screenshots | (menu is in trailing HStack)
                    HStack(alignment: .top, spacing: CursorTheme.spaceS) {
                        Text(task.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(task.completed ? CursorTheme.textTertiary(for: colorScheme) : CursorTheme.textPrimary(for: colorScheme))
                            .strikethrough(task.completed)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if canOpenLinkedAgent {
                                    onTap()
                                }
                            }
                            .onTapGesture(count: 2) { if !task.completed, !isProcessing { onTap() } }
                        if !task.screenshotPaths.isEmpty {
                            TaskScreenshotStripView(
                                workspacePath: workspacePath,
                                paths: task.screenshotPaths,
                                onPreview: { onPreviewScreenshot?($0) },
                                onDelete: onDeleteScreenshot
                            )
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                if !task.completed, !models.isEmpty, !isEditing {
                    ModelPickerView(
                        selectedModelId: task.modelId,
                        models: models,
                        onSelect: { onModelChange?($0) }
                    )
                    .disabled(isProcessing)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if isProcessing, let onStopAgent {
                Menu {
                    Button("Stop agent", systemImage: "stop.fill") {
                        onStopAgent()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else if !isProcessing {
                Menu {
                    if canOpenLinkedAgent {
                        Button("Open linked Agent", systemImage: "arrow.up.right") {
                            onTap()
                        }
                        if let onContinueAgent {
                            Button("Continue", systemImage: "play.fill") {
                                onContinueAgent()
                            }
                        }
                        Divider()
                    }
                    if !task.completed {
                        if canDelegate {
                            Button("Delegate", systemImage: "person") {
                                onSendToAgent()
                            }
                        }
                        if canEdit {
                            Button("Edit", systemImage: "pencil") {
                                onTap()
                            }
                        }
                        if let stateTransitionLabel, let onStateTransition {
                            Button(stateTransitionLabel, systemImage: stateTransitionIcon) {
                                onStateTransition()
                            }
                        }
                        Divider()
                    }
                    Button(task.completed ? "Mark as not done" : "Complete", systemImage: task.completed ? "circle" : "checkmark.circle") {
                        onToggleComplete()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .contextMenu {
            if canOpenLinkedAgent {
                Button("Open linked Agent", systemImage: "arrow.up.right") {
                    onTap()
                }
                if let onContinueAgent {
                    Button("Continue", systemImage: "play.fill") {
                        onContinueAgent()
                    }
                }
                Divider()
            }
            if canDelegate {
                Button("Delegate", systemImage: "person") {
                    onSendToAgent()
                }
                .disabled(isProcessing)
            }
            if task.taskState != .completed {
                if canEdit {
                    Button("Edit", systemImage: "pencil") {
                        onTap()
                    }
                    .disabled(isProcessing)
                }
                if let stateTransitionLabel, let onStateTransition {
                    Button(stateTransitionLabel, systemImage: stateTransitionIcon) {
                        onStateTransition()
                    }
                    .disabled(isProcessing)
                }
                Divider()
            }
            Button(task.completed ? "Mark as not done" : "Complete", systemImage: task.completed ? "circle" : "checkmark.circle") {
                onToggleComplete()
            }
            .disabled(isProcessing)
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
            .disabled(isProcessing)
        }
    }

}
