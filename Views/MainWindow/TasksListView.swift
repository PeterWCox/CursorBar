import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tasks (todos) list for a project

/// One tab per task state.
enum TasksListTab: String, CaseIterable {
    case backlog = "Backlog"
    case todo = "In Review"
    case processing = "Processing"
    case finished = "Review"
    case completed = "Completed"
    case deleted = "Deleted"
}

struct TasksListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    /// When set to true from outside (e.g. Cmd+T), show the add-new-task row and focus it.
    var triggerAddNewTask: Binding<Bool> = .constant(false)
    /// Linked agent status per task ID (open / processing / done / stopped) so the task row can show a badge. Passed from parent so the list updates when tabs run/complete.
    var linkedStatuses: [UUID: LinkedTaskStatus] = [:]
    /// Models to show in the task model picker (same as input bar).
    var models: [ModelOption]
    /// Send task content to a new agent; when taskID is non-nil, the new agent is linked to that task. When screenshotPaths is non-empty, those paths (under .metro) are attached to the prompt. modelId is the task's chosen model (e.g. "auto").
    var onSendToAgent: (String, UUID?, [String], String) -> Void
    /// Open the linked agent for a task when the row represents active or completed agent work.
    var onOpenLinkedAgent: (ProjectTask) -> Void = { _ in }
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
    /// Which top-level tab is selected: In Progress, Backlog, or Archive.
    @State private var selectedTasksTab: TasksListTab = .todo

    private static let completedRecentInterval: TimeInterval = 24 * 60 * 60

    private func reloadTasks() {
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
        deletedTasksList = ProjectTasksStorage.deletedTasks(workspacePath: workspacePath)
    }

    private var todoTasks: [ProjectTask] {
        tasks.filter { task in
            guard !task.completed, !task.backlog else { return false }
            let status = linkedStatuses[task.id]
            return status != .processing && status != .done
        }
    }

    private var backlogTasks: [ProjectTask] {
        tasks.filter { task in
            guard !task.completed, task.backlog else { return false }
            let status = linkedStatuses[task.id]
            return status != .processing && status != .done
        }
    }

    /// Tasks currently being processed by a linked agent.
    private var processingTasks: [ProjectTask] {
        tasks.filter { linkedStatuses[$0.id] == .processing }
    }

    /// Tasks whose linked agent has finished (done or stopped) and need review. Excludes completed tasks so they only appear in Completed.
    private var finishedTasks: [ProjectTask] {
        tasks.filter { task in
            guard !task.completed else { return false }
            let s = linkedStatuses[task.id]
            return s == .done || s == .stopped
        }
    }

    private var completedTasks: [ProjectTask] {
        tasks.filter(\.completed)
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
            let asBacklog = (selectedTasksTab == .backlog)
            _ = ProjectTasksStorage.addTask(workspacePath: workspacePath, content: trimmed, screenshotImages: newTaskDraftScreenshots.map(\.image), modelId: newTaskModelId, backlog: asBacklog)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadTasks()
            // Handle Cmd+T when it fired before this view was in the hierarchy (trigger already true).
            if triggerAddNewTask.wrappedValue {
                showNewTaskComposer(selecting: .todo)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: workspacePath) { _, _ in reloadTasks() }
        .onChange(of: triggerAddNewTask.wrappedValue) { _, requested in
            if requested {
                showNewTaskComposer(selecting: .todo)
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
        case .todo: return todoTasks.count
        case .processing: return processingTasks.count
        case .finished: return finishedTasks.count
        case .completed: return completedTasks.count
        case .deleted: return deletedTasksList.count
        }
    }

    private var tasksTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TasksListTab.allCases, id: \.self) { tab in
                Button {
                    selectedTasksTab = tab
                    if tab != .todo && tab != .backlog && isAddingNewTask {
                        isAddingNewTask = false
                        cancelNewTask()
                    }
                } label: {
                    Text("\(tab.rawValue) (\(taskCount(for: tab)))")
                        .font(.system(size: 13, weight: selectedTasksTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTasksTab == tab ? (tab == .finished ? CursorTheme.semanticReview : CursorTheme.textPrimary(for: colorScheme)) : CursorTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, CursorTheme.spaceM)
                        .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
                }
                .buttonStyle(.plain)
                .background(selectedTasksTab == tab ? (tab == .finished ? CursorTheme.semanticReview.opacity(0.2) : CursorTheme.surfaceMuted(for: colorScheme)) : Color.clear)
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
        case .todo:
            todoContent
        case .backlog:
            backlogContent
        case .processing:
            processingContent
        case .finished:
            finishedContent
        case .completed:
            completedContent
        case .deleted:
            deletedContent
        }
    }

    @ViewBuilder
    private var todoContent: some View {
        newTaskButton
        let isEmpty = todoTasks.isEmpty && !isAddingNewTask
        if isEmpty {
            emptyState
        } else {
            if isAddingNewTask {
                newTaskRow
            }
            ForEach(todoTasks) { task in
                taskRow(task, isInBacklog: false, onToggleBacklog: {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: true)
                    reloadTasks()
                })
            }
        }
    }

    private var newTaskButton: some View {
        Button(action: {
            showNewTaskComposer()
        }) {
            Label("New task", systemImage: "plus.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CursorTheme.brandBlue)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CursorTheme.spaceS)
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
                taskRow(task, isInBacklog: true, onToggleBacklog: {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: false)
                    reloadTasks()
                })
            }
        }
    }

    @ViewBuilder
    private var processingContent: some View {
        if processingTasks.isEmpty {
            emptyStateProcessing
        } else {
            ForEach(processingTasks) { task in
                taskRow(task, isInBacklog: task.backlog, onToggleBacklog: task.backlog ? {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: false)
                    reloadTasks()
                } : {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: true)
                    reloadTasks()
                })
            }
        }
    }

    @ViewBuilder
    private var finishedContent: some View {
        if finishedTasks.isEmpty {
            emptyStateFinished
        } else {
            ForEach(finishedTasks) { task in
                taskRow(task, isInBacklog: task.backlog, onToggleBacklog: task.backlog ? {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: false)
                    reloadTasks()
                } : {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, backlog: true)
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
    private func taskRow(_ task: ProjectTask, isInBacklog: Bool = false, onToggleBacklog: (() -> Void)? = nil) -> some View {
        TaskRowView(
            task: task,
            workspacePath: workspacePath,
            models: models,
            linkedTaskStatus: linkedStatuses[task.id],
            isEditing: editingTask?.id == task.id,
            editDraft: $editingDraft,
            isEditorFocused: $isTaskEditorFocused,
            onTap: {
                if linkedStatuses[task.id] != nil {
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
                ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, completed: !task.completed)
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
            isInBacklog: isInBacklog,
            onToggleBacklog: onToggleBacklog
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
            Text("Move tasks here from In Review when you want to work on them later.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CursorTheme.spaceXXL + CursorTheme.spaceL)
    }

    private var emptyStateProcessing: some View {
        emptyStatePlaceholder(
            icon: "gearshape.2",
            title: "No tasks processing",
            subtitle: "Tasks sent to an agent appear here while they run."
        )
    }

    private var emptyStateFinished: some View {
        emptyStatePlaceholder(
            icon: "checkmark.circle",
            title: "No tasks to review",
            subtitle: "Tasks whose agent run has completed or stopped appear here."
        )
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .symbolRenderingMode(.hierarchical)
            Text("No tasks yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            Text("Add a task to track work for this project. You can send any task to a new agent tab.")
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
    var onTapPreview: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var imageURL: URL {
        ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
    }

    var body: some View {
        ScreenshotThumbnailView(
            imageURL: imageURL,
            size: CGSize(width: 56, height: 56),
            cornerRadius: 6,
            onTapPreview: onTapPreview,
            onDelete: onDelete
        )
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: ProjectTask
    let workspacePath: String
    var models: [ModelOption] = []
    /// When set, the leading icon reflects the linked agent status (processing / done / open / stopped).
    var linkedTaskStatus: LinkedTaskStatus? = nil
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
    var isInBacklog: Bool = false
    var onToggleBacklog: (() -> Void)? = nil

    private var isProcessing: Bool { linkedTaskStatus == .processing }
    private var canOpenLinkedAgent: Bool { linkedTaskStatus == .processing || linkedTaskStatus == .done || linkedTaskStatus == .stopped }

    @ViewBuilder
    private var leadingIcon: some View {
        if linkedTaskStatus == .processing {
            LightBlueSpinner(size: 18)
        } else if linkedTaskStatus == .done {
            Image(systemName: "clock.fill")
                .font(.system(size: 18))
                .foregroundStyle(CursorTheme.semanticReview)
        } else if linkedTaskStatus == .stopped {
            Image(systemName: "clock.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CursorTheme.semanticReview)
        } else if task.completed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(CursorTheme.brandBlue)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 18))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if isProcessing {
                    leadingIcon
                } else {
                    Button(action: onToggleComplete) {
                        leadingIcon
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditing)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
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
                    HStack(alignment: .top, spacing: 8) {
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
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                if !task.screenshotPaths.isEmpty && !(isEditing && !task.completed) {
                    HStack(alignment: .center, spacing: 6) {
                        ForEach(task.screenshotPaths, id: \.self) { path in
                            TaskScreenshotThumbnailView(
                                workspacePath: workspacePath,
                                screenshotPath: path,
                                onTapPreview: { onPreviewScreenshot?(path) },
                                onDelete: { onDeleteScreenshot?(path) }
                            )
                        }
                    }
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

            if !isProcessing {
                Menu {
                    if canOpenLinkedAgent {
                        Button("Open linked Agent", systemImage: "arrow.up.right") {
                            onTap()
                        }
                        Divider()
                    }
                    if !task.completed {
                        Button("Delegate", systemImage: "person") {
                            onSendToAgent()
                        }
                        Button("Edit", systemImage: "pencil") {
                            onTap()
                        }
                        if let onToggleBacklog {
                            Button(isInBacklog ? "In Review" : "Backlog", systemImage: isInBacklog ? "circle.list" : "tray.full") {
                                onToggleBacklog()
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
                Divider()
            }
            if !task.completed {
                Button("Delegate", systemImage: "person") {
                    onSendToAgent()
                }
                .disabled(isProcessing)
                Button("Edit", systemImage: "pencil") {
                    onTap()
                }
                .disabled(isProcessing)
                if let onToggleBacklog {
                    Button(isInBacklog ? "In Review" : "Backlog", systemImage: isInBacklog ? "circle.list" : "tray.full") {
                        onToggleBacklog()
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
