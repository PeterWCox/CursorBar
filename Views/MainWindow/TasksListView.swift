import SwiftUI
import AppKit

// MARK: - Tasks (todos) list for a project

private struct TasksTabBarView: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme

    let selectedTab: TasksListTab
    let counts: TasksTabCounts
    let onSelect: (TasksListTab) -> Void

    static func == (lhs: TasksTabBarView, rhs: TasksTabBarView) -> Bool {
        lhs.selectedTab == rhs.selectedTab && lhs.counts == rhs.counts
    }

    private func tabLabel(for tab: TasksListTab) -> String {
        let c = counts.count(for: tab)
        return c > 0 ? "\(tab.rawValue) (\(c))" : tab.rawValue
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TasksListTab.allCases, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    Text(tabLabel(for: tab))
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, CursorTheme.spaceM)
                        .padding(.vertical, CursorTheme.spaceS + CursorTheme.spaceXXS)
                }
                .buttonStyle(.plain)
                .background(selectedTab == tab ? CursorTheme.surfaceMuted(for: colorScheme) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CursorTheme.paddingHeaderHorizontal)
        .padding(.vertical, CursorTheme.spaceXS)
        .background(CursorTheme.chrome(for: colorScheme))
    }
}

// MARK: - Collapsible grouping (Completed / Deleted time buckets)

/// Reusable collapsible section: header (icon + title + count) with expand/collapse and a list of cards.
private struct CollapsibleGroupingView<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let count: Int
    let icon: String
    let isExpanded: Bool
    let onToggle: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        count: Int,
        icon: String = "calendar",
        isExpanded: Bool,
        onToggle: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.icon = icon
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.content = content
    }

    var body: some View {
        if count > 0 {
            DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { onToggle($0) })) {
                VStack(alignment: .leading, spacing: CursorTheme.spacingListItems) {
                    content()
                }
                .padding(.top, CursorTheme.gapSectionTitleToContent)
            } label: {
                HStack(spacing: CursorTheme.spaceXS) {
                    Image(systemName: icon)
                        .font(.system(size: CursorTheme.fontIconList))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    Text(title)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    Text("(\(count))")
                        .font(.system(size: CursorTheme.fontCaption, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .frame(height: CursorTheme.fontIconList)
            }
            .padding(.top, CursorTheme.spaceM)
            .padding(.bottom, CursorTheme.gapBetweenSections)
            .id("grouping-\(title)")
        }
    }
}

private struct DraftTaskScreenshot: Identifiable {
    let id: UUID
    let image: NSImage
    let pngData: Data

    init(id: UUID = UUID(), image: NSImage, pngData: Data) {
        self.id = id
        self.image = image
        self.pngData = pngData
    }

    init?(id: UUID = UUID(), pngData: Data) {
        guard let image = NSImage(data: pngData) else { return nil }
        self.init(id: id, image: image, pngData: pngData)
    }
}

struct TasksListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    /// When set to true from outside (e.g. Cmd+T), show the add-new-task row and focus it.
    var triggerAddNewTask: Binding<Bool> = .constant(false)
    /// Linked agent status per task ID so the task row can show review/processing state separately from task lifecycle.
    var linkedStatuses: [UUID: AgentTaskState] = [:]
    /// Provider used for new tasks created from this Tasks view.
    var newTaskProviderID: AgentProviderID
    /// Returns visible model options for the given provider.
    var modelsForProvider: (AgentProviderID) -> [ModelOption]
    /// Send task content to a new agent; when taskID is non-nil, the new agent is linked to that task. When screenshotPaths is non-empty, those paths (under .metro) are attached to the prompt. providerID + modelId capture the task's current agent configuration.
    var onSendToAgent: (String, UUID?, [String], AgentProviderID, String) -> Void
    /// Open the linked agent for a task when the row represents active or completed agent work.
    var onOpenLinkedAgent: (ProjectTask) -> Void = { _ in }
    /// Continue a stopped agent: focus its tab and send the "continue" prompt.
    var onContinueAgent: (ProjectTask) -> Void = { _ in }
    /// Reset a stopped agent: close the linked tab and start a fresh agent with the task content.
    var onResetAgent: (ProjectTask) -> Void = { _ in }
    /// Stop the agent currently running for a task (from the Processing section).
    var onStopAgent: (ProjectTask) -> Void = { _ in }
    /// Called when any task is updated (e.g. completed, edited) so the sidebar can refresh (e.g. hide agent tabs for completed tasks).
    var onTasksDidUpdate: () -> Void = { }
    var onDismiss: () -> Void
    /// When false, the list does not show its own header (e.g. when the panel title row already shows "Tasks" + project).
    var showHeader: Bool = true
    /// Launch setup agent or open Advanced for this project (Configure Setup button). When nil, Configure Setup is omitted.
    var onLaunchSetupAgent: ((String) -> Void)? = nil

    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @StateObject private var store = TasksListStore()
    @State private var focusNewTaskField: (() -> Void)?
    /// Height of the new-task text editor; grows with content so multi-line draft is fully visible.
    @State private var newTaskEditorHeight: CGFloat = 24
    /// URLs and paths for full-screen task screenshot preview (saved task screenshots). When non-empty, modal shows images side by side.
    @State private var taskScreenshotPreviewURLs: [URL] = []
    @State private var taskScreenshotPreviewPaths: [String] = []
    @State private var taskScreenshotPreviewIndex: Int = 0
    /// Delete callback for the task whose screenshots are being previewed; used by modal X to remove a screenshot.
    @State private var taskScreenshotPreviewOnDelete: ((String) -> Void)? = nil
    /// In-memory image for full-screen preview (new-task draft screenshots before save).
    @State private var taskScreenshotPreviewImage: NSImage? = nil
    /// Draft screenshots for the new task row (paste before commit). Shown with same thumbnail + preview as existing tasks.
    @State private var newTaskDraftScreenshots: [DraftTaskScreenshot] = []
    /// Draft screenshots while editing an existing task. Existing screenshots are loaded into memory and replaced on save.
    @State private var editDraftScreenshots: [DraftTaskScreenshot] = []
    /// Height of the edit-task text editor; grows with content so multi-line draft is fully visible.
    @State private var editTaskEditorHeight: CGFloat = 36

    private var preferredTerminal: PreferredTerminalApp {
        PreferredTerminalApp(rawValue: preferredTerminalAppRawValue) ?? .automatic
    }

    private func reloadTasks() {
        store.configure(workspacePath: workspacePath, linkedStatuses: linkedStatuses)
    }

    private var taskSnapshot: TasksListSnapshot {
        store.snapshot
    }

    private func models(for providerID: AgentProviderID) -> [ModelOption] {
        let available = modelsForProvider(providerID)
        return available.isEmpty ? AgentProviders.fallbackModels(for: providerID) : available
    }

    private func syncNewTaskModelSelection() {
        let available = models(for: newTaskProviderID)
        guard let fallback = available.first else { return }
        if !available.contains(where: { $0.id == store.newTaskModelId }) {
            store.newTaskModelId = fallback.id
        }
    }

    private func loadDraftScreenshots(for task: ProjectTask) -> [DraftTaskScreenshot] {
        task.screenshotPaths.compactMap { path in
            let url = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return DraftTaskScreenshot(pngData: data)
        }
    }

    private func materializedScreenshot(from image: NSImage) -> DraftTaskScreenshot? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]),
              let screenshot = DraftTaskScreenshot(pngData: pngData) else {
            return nil
        }

        return screenshot
    }

    private func appendScreenshot(to screenshots: inout [DraftTaskScreenshot], from pasteboard: NSPasteboard = .general) {
        guard screenshots.count < AppLimits.maxScreenshots,
              let pastedImage = SubmittableTextEditor.imageFromPasteboard(pasteboard),
              let image = materializedScreenshot(from: pastedImage) else {
            return
        }

        screenshots.append(image)
    }

    private func pasteNewTaskScreenshot() {
        appendScreenshot(to: &newTaskDraftScreenshots)
    }

    private func pasteEditScreenshot() {
        appendScreenshot(to: &editDraftScreenshots)
    }

    private func beginEditing(_ task: ProjectTask) {
        let content = task.content
        let screenshots = loadDraftScreenshots(for: task)

        DispatchQueue.main.async {
            store.editingDraft = content
            editDraftScreenshots = screenshots
            taskScreenshotPreviewImage = nil
            store.editingTask = task
        }
    }

    private func commitNewTask() {
        syncNewTaskModelSelection()
        store.commitNewTask(
            screenshotData: newTaskDraftScreenshots.map(\.pngData),
            providerID: newTaskProviderID
        )
        newTaskDraftScreenshots = []
    }

    private func cancelNewTask() {
        store.cancelNewTask()
        newTaskDraftScreenshots = []
        taskScreenshotPreviewImage = nil
    }

    private func commitEdit() {
        store.commitEdit(screenshotData: editDraftScreenshots.map(\.pngData))
        editDraftScreenshots = []
        taskScreenshotPreviewImage = nil
    }

    private func cancelEdit() {
        store.editingTask = nil
        editDraftScreenshots = []
        taskScreenshotPreviewImage = nil
    }

    private func showNewTaskComposer(selecting tab: TasksListTab? = nil) {
        store.showNewTaskComposer(selecting: tab)
        newTaskDraftScreenshots = []
        taskScreenshotPreviewImage = nil
        syncNewTaskModelSelection()
    }

    private func selectTasksTab(_ tab: TasksListTab) {
        let wasAddingNewTask = store.isAddingNewTask
        store.selectTasksTab(tab)
        if wasAddingNewTask && !store.isAddingNewTask {
            newTaskDraftScreenshots = []
            taskScreenshotPreviewImage = nil
        }
    }

    private func delegateTask(_ task: ProjectTask) {
        let persistedTask = ProjectTasksStorage.task(workspacePath: workspacePath, id: task.id) ?? task
        onSendToAgent(
            persistedTask.content,
            persistedTask.id,
            persistedTask.screenshotPaths,
            persistedTask.providerID,
            persistedTask.modelId
        )
    }

    var body: some View {
        let snapshot = taskSnapshot
        VStack(spacing: 0) {
            if showHeader { header }
            TasksTabBarView(
                selectedTab: store.selectedTasksTab,
                counts: snapshot.counts,
                onSelect: selectTasksTab
            )
            .equatable()
            Divider()
                .background(CursorTheme.border(for: colorScheme))
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: CursorTheme.spacingListItems) {
                        Color.clear
                            .frame(height: 0)
                            .id("tasksScrollTop")
                        tabContent(snapshot: snapshot)
                            .id(store.selectedTasksTab)
                    }
                    .padding(CursorTheme.paddingPanel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: store.isAddingNewTask) { _, showing in
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
            syncNewTaskModelSelection()
            // Handle Cmd+T when it fired before this view was in the hierarchy (trigger already true).
            if triggerAddNewTask.wrappedValue {
                showNewTaskComposer(selecting: .inProgress)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: workspacePath) { _, _ in
            reloadTasks()
            syncNewTaskModelSelection()
        }
        .onChange(of: linkedStatuses) { _, newStatuses in store.updateLinkedStatuses(newStatuses) }
        .onChange(of: newTaskProviderID) { _, _ in
            syncNewTaskModelSelection()
        }
        .onChange(of: triggerAddNewTask.wrappedValue) { _, requested in
            if requested {
                showNewTaskComposer(selecting: .inProgress)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: store.isAddingNewTask) { _, showing in
            if showing {
                DispatchQueue.main.async {
                    focusNewTaskField?()
                }
            }
        }
        .overlay {
            if !taskScreenshotPreviewURLs.isEmpty || taskScreenshotPreviewImage != nil {
                ScreenshotPreviewModal(
                    imageURLs: taskScreenshotPreviewURLs.isEmpty ? nil : taskScreenshotPreviewURLs,
                    initialIndex: taskScreenshotPreviewIndex,
                    image: taskScreenshotPreviewImage,
                    isPresented: Binding(
                        get: { true },
                        set: { if !$0 { taskScreenshotPreviewURLs = []; taskScreenshotPreviewPaths = []; taskScreenshotPreviewIndex = 0; taskScreenshotPreviewImage = nil; taskScreenshotPreviewOnDelete = nil } }
                    ),
                    onDeleteScreenshotAtIndex: taskScreenshotPreviewOnDelete != nil && !taskScreenshotPreviewPaths.isEmpty ? { index in
                        guard index >= 0, index < taskScreenshotPreviewPaths.count else { return }
                        let path = taskScreenshotPreviewPaths[index]
                        taskScreenshotPreviewOnDelete?(path)
                        taskScreenshotPreviewPaths.remove(at: index)
                        taskScreenshotPreviewURLs.remove(at: index)
                        if taskScreenshotPreviewURLs.isEmpty {
                            taskScreenshotPreviewOnDelete = nil
                            taskScreenshotPreviewIndex = 0
                        } else {
                            taskScreenshotPreviewIndex = min(taskScreenshotPreviewIndex, taskScreenshotPreviewURLs.count - 1)
                        }
                    } : nil
                )
            }
        }
    }

    @ViewBuilder
    private func tabContent(snapshot: TasksListSnapshot) -> some View {
        switch store.selectedTasksTab {
        case .inProgress:
            inProgressContent(snapshot: snapshot)
        case .backlog:
            backlogContent(snapshot: snapshot)
        case .completed:
            completedContent(snapshot: snapshot)
        case .deleted:
            deletedContent(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func inProgressContent(snapshot: TasksListSnapshot) -> some View {
        previewButtonsBar
            .padding(.bottom, CursorTheme.spaceS)
        let isEmpty = snapshot.counts.inProgress == 0 && !store.isAddingNewTask
        if isEmpty {
            emptyStateInProgress
        } else {
            if store.isAddingNewTask {
                newTaskRow
            }
            inProgressSection(title: "Todo", rows: snapshot.todoRows)
            inProgressSection(title: "Processing", rows: snapshot.processingRows)
            inProgressSection(title: "Review", rows: snapshot.reviewRows)
            inProgressSection(title: "Stopped", rows: snapshot.stoppedRows)
        }
    }

    /// Shared Add Task chip used in In Progress bar and Backlog (same as Fix build / Commit & push).
    private var addTaskChip: some View {
        ActionButton(
            title: "Add Task",
            icon: "plus.circle.fill",
            action: { showNewTaskComposer() },
            help: "Add task (⌘T)",
            style: .primary
        )
    }

    /// Add Task only; Play / Stop / Configure Setup / Open in Browser are in the Preview view header.
    private var previewButtonsBar: some View {
        HStack(spacing: CursorTheme.spaceS) {
            addTaskChip
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inProgressSection(title: String, rows scopedTasks: [SectionScopedTaskRow]) -> some View {
        if !scopedTasks.isEmpty {
            VStack(alignment: .leading, spacing: CursorTheme.gapSectionTitleToContent) {
                HStack(spacing: CursorTheme.spaceXS) {
                    sectionStatusIcon(title: title)
                        .frame(width: CursorTheme.fontIconList, height: CursorTheme.fontIconList)
                    Text(title)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                        .foregroundStyle(
                            title == "Review" ? CursorTheme.semanticReview
                            : title == "Stopped" ? CursorTheme.semanticError
                            : CursorTheme.textSecondary(for: colorScheme)
                        )
                }
                .frame(height: CursorTheme.fontIconList)
                ForEach(scopedTasks) { item in
                    let task = item.task
                    let canMoveToBacklog = linkedStatuses[task.id] == nil || linkedStatuses[task.id] == .none
                    taskRow(
                        task,
                        stateTransitionLabel: canMoveToBacklog ? "Backlog" : nil,
                        stateTransitionIcon: "tray.full",
                        onStateTransition: canMoveToBacklog ? {
                            store.moveTask(task, to: .backlog)
                        } : nil
                    )
                }
            }
            .padding(.top, CursorTheme.spaceM)
            .padding(.bottom, CursorTheme.gapBetweenSections)
            .id(title)
        }
    }

    @ViewBuilder
    private func timeBucketSection(
        title: String,
        tasks: [ProjectTask],
        @ViewBuilder showTaskRow: @escaping (ProjectTask) -> some View
    ) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: CursorTheme.gapSectionTitleToContent) {
                HStack(spacing: CursorTheme.spaceXS) {
                    Image(systemName: "calendar")
                        .font(.system(size: CursorTheme.fontIconList))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    Text(title)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                }
                .frame(height: CursorTheme.fontIconList)
                ForEach(tasks) { task in
                    showTaskRow(task)
                }
            }
            .padding(.top, CursorTheme.spaceM)
            .padding(.bottom, CursorTheme.gapBetweenSections)
            .id("bucket-\(title)")
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
                LightBlueSpinner(size: CursorTheme.fontIconList - 4)
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

    @ViewBuilder
    private func backlogContent(snapshot: TasksListSnapshot) -> some View {
        HStack(spacing: CursorTheme.spaceS) {
            addTaskChip
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CursorTheme.spaceS)
        let isEmpty = snapshot.backlogTasks.isEmpty && !store.isAddingNewTask
        if isEmpty {
            emptyStateBacklog
        } else {
            if store.isAddingNewTask {
                newTaskRow
            }
            ForEach(snapshot.backlogTasks) { task in
                taskRow(task, stateTransitionLabel: "In Progress", stateTransitionIcon: "arrow.right.circle", onStateTransition: {
                    store.moveTask(task, to: .inProgress)
                })
            }
        }
    }

    @ViewBuilder
    private func completedContent(snapshot: TasksListSnapshot) -> some View {
        if snapshot.visibleCompletedTasks.isEmpty {
            emptyStateCompleted
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.completedGrouped) { group in
                    CollapsibleGroupingView(
                        title: group.title,
                        count: group.tasks.count,
                        icon: "calendar",
                        isExpanded: store.expandedCompletedSections.contains(group.title),
                        onToggle: { expanded in store.setCompletedSectionExpanded(group.title, expanded: expanded) },
                        content: {
                            ForEach(group.tasks) { task in
                                taskRow(task)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, CursorTheme.spaceM)
            .padding(.top, CursorTheme.spaceS)
        }
    }

    @ViewBuilder
    private func deletedContent(snapshot: TasksListSnapshot) -> some View {
        if snapshot.deletedTasks.isEmpty {
            emptyStateDeleted
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(snapshot.deletedGrouped) { group in
                    CollapsibleGroupingView(
                        title: group.title,
                        count: group.tasks.count,
                        icon: "calendar",
                        isExpanded: store.expandedDeletedSections.contains(group.title),
                        onToggle: { expanded in store.setDeletedSectionExpanded(group.title, expanded: expanded) },
                        content: {
                            ForEach(group.tasks) { task in
                                deletedTaskRow(task)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, CursorTheme.spaceM)
            .padding(.top, CursorTheme.spaceS)
        }
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
            models: models(for: task.providerID),
            agentTaskState: linkedStatuses[task.id] ?? .none,
            isEditing: store.editingTask?.id == task.id,
            editDraft: $store.editingDraft,
            editScreenshots: store.editingTask?.id == task.id ? editDraftScreenshots : [],
            onTap: {
                if let linkedState = linkedStatuses[task.id], linkedState != AgentTaskState.none {
                    onOpenLinkedAgent(task)
                } else {
                    beginEditing(task)
                }
            },
            onCommitEdit: commitEdit,
            onCancelEdit: cancelEdit,
            onToggleComplete: {
                store.toggleTaskCompletion(task)
                onTasksDidUpdate()
            },
            onSendToAgent: { delegateTask(task) },
            onModelChange: { newId in
                store.updateTaskModel(task, modelId: newId)
            },
            onDelete: {
                store.deleteTask(task)
            },
            onPreviewScreenshot: { paths, selectedPath, onDelete in
                taskScreenshotPreviewURLs = paths.map { ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: $0) }
                taskScreenshotPreviewPaths = paths
                taskScreenshotPreviewIndex = paths.firstIndex(of: selectedPath) ?? 0
                taskScreenshotPreviewOnDelete = onDelete
            },
            onDeleteScreenshot: !task.completed ? { path in
                store.removeTaskScreenshot(taskID: task.id, screenshotPath: path)
            } : nil,
            onPasteEditScreenshot: store.editingTask?.id == task.id ? pasteEditScreenshot : nil,
            onPreviewEditScreenshot: { image in
                taskScreenshotPreviewImage = image
            },
            onRemoveEditScreenshot: { screenshotID in
                if let screenshot = editDraftScreenshots.first(where: { $0.id == screenshotID }),
                   taskScreenshotPreviewImage === screenshot.image {
                    taskScreenshotPreviewImage = nil
                }
                editDraftScreenshots.removeAll { $0.id == screenshotID }
            },
            stateTransitionLabel: stateTransitionLabel,
            stateTransitionIcon: stateTransitionIcon,
            onStateTransition: onStateTransition,
            onStopAgent: linkedStatuses[task.id] == .processing ? { onStopAgent(task) } : nil,
            onContinueAgent: linkedStatuses[task.id] == .stopped ? { onContinueAgent(task) } : nil,
            onResetAgent: linkedStatuses[task.id] == .stopped ? { onResetAgent(task) } : nil,
            editEditorHeight: editTaskEditorHeight,
            onEditEditorHeightChange: { editTaskEditorHeight = $0 }
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
                    store.restoreTask(task)
                }
                Divider()
                Button("Delete permanently", systemImage: "trash", role: .destructive) {
                    store.permanentlyDeleteTask(task)
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
                store.restoreTask(task)
            }
            Divider()
            Button("Delete permanently", systemImage: "trash", role: .destructive) {
                store.permanentlyDeleteTask(task)
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
                        .foregroundStyle(CursorTheme.colorForWorkspace(path: workspacePath))
                    Text((store.workspacePath as NSString).lastPathComponent)
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.colorForWorkspace(path: workspacePath))
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
                    SubmittableTextEditor(
                        text: $store.newTaskDraft,
                        isDisabled: false,
                        onSubmit: commitNewTask,
                        onPasteImage: pasteNewTaskScreenshot,
                        onHeightChange: { newTaskEditorHeight = $0 },
                        onFocusRequested: { focus, _ in
                            focusNewTaskField = focus
                            if store.isAddingNewTask {
                                DispatchQueue.main.async {
                                    focus()
                                }
                            }
                        },
                        colorScheme: colorScheme,
                        font: NSFont.systemFont(ofSize: 14, weight: .regular),
                        textContainerInset: NSSize(width: 0, height: 4)
                    )
                        .onKeyPress(.escape) {
                            cancelNewTask()
                            return .handled
                        }
                        .frame(height: min(400, max(24, newTaskEditorHeight)))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -4)
                    if store.newTaskDraft.isEmpty {
                        Text(newTaskDraftScreenshots.isEmpty ? "Add task…" : "Describe the task…")
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
                    selectedModelId: store.newTaskModelId,
                    models: models(for: newTaskProviderID),
                    onSelect: { store.newTaskModelId = $0 }
                )
            }
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
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

// MARK: - Inline screenshot strip: thumbnails shown side by side (each with delete X)

private struct TaskScreenshotStripView: View {
    let workspacePath: String
    let paths: [String]
    var thumbnailSize: CGSize = CGSize(width: 36, height: 36)
    /// Called with (all paths, selected path) so expanded preview can show side-by-side.
    var onPreview: ([String], String) -> Void = { _, _ in }
    var onDelete: ((String) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if paths.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: CursorTheme.spaceS) {
                ForEach(paths, id: \.self) { path in
                    TaskScreenshotThumbnailView(
                        workspacePath: workspacePath,
                        screenshotPath: path,
                        size: thumbnailSize,
                        onTapPreview: { onPreview(paths, path) },
                        onDelete: onDelete.map { cb in { cb(path) } }
                    )
                }
            }
        }
    }
}

private struct TaskScreenshotSummaryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let workspacePath: String
    let screenshotPath: String
    let screenshotCount: Int
    var thumbnailSize: CGSize = TaskRowView.compactScreenshotSize
    var onOpenPreview: (() -> Void)? = nil

    private var imageURL: URL {
        ProjectTasksStorage.taskScreenshotFileURL(
            workspacePath: workspacePath,
            screenshotPath: screenshotPath
        )
    }

    private var previewImage: NSImage? {
        ImageAssetCache.shared.screenshot(for: imageURL)
    }

    private var badgeText: String {
        screenshotCount > 99 ? "99+" : "\(screenshotCount)"
    }

    var body: some View {
        ScreenshotThumbnailView(
            image: previewImage,
            size: thumbnailSize,
            cornerRadius: CursorTheme.spaceS
        )
        .overlay(alignment: .topTrailing) {
            Text(badgeText)
                .font(.system(size: CursorTheme.fontCaption, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, CursorTheme.paddingBadgeHorizontal)
                .padding(.vertical, CursorTheme.paddingBadgeVertical)
                .background(CursorTheme.surface(for: colorScheme), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CursorTheme.borderStrong(for: colorScheme), lineWidth: 1)
                )
                .padding(CursorTheme.spaceXS)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(screenshotCount) screenshots attached")
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpenPreview?()
        }
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    static let inlineScreenshotSize = CGSize(width: 56, height: 56)
    static let compactScreenshotSize = CGSize(width: 42, height: 42)
    let task: ProjectTask
    let workspacePath: String
    var models: [ModelOption] = []
    /// Agent state is independent from the task lifecycle and drives the In Progress grouping.
    var agentTaskState: AgentTaskState = .none
    var isEditing: Bool = false
    @Binding var editDraft: String
    var editScreenshots: [DraftTaskScreenshot] = []
    let onTap: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onToggleComplete: () -> Void
    let onSendToAgent: () -> Void
    var onModelChange: ((String) -> Void)? = nil
    let onDelete: () -> Void
    var onPreviewScreenshot: (([String], String, ((String) -> Void)?) -> Void)? = nil
    var onDeleteScreenshot: ((String) -> Void)? = nil
    var onPasteEditScreenshot: (() -> Void)? = nil
    var onPreviewEditScreenshot: ((NSImage) -> Void)? = nil
    var onRemoveEditScreenshot: ((UUID) -> Void)? = nil
    var stateTransitionLabel: String? = nil
    var stateTransitionIcon: String = "arrow.right.circle"
    var onStateTransition: (() -> Void)? = nil
    /// When non-nil (processing tasks), the row shows a 3-dot menu with a single "Stop" item.
    var onStopAgent: (() -> Void)? = nil
    /// When non-nil (stopped tasks), the row shows "Continue" which focuses the agent and sends "continue".
    var onContinueAgent: (() -> Void)? = nil
    /// When non-nil (stopped tasks), the row shows "Reset agent" which closes the linked agent and starts a fresh one.
    var onResetAgent: (() -> Void)? = nil
    /// Current height of the edit text editor (from onEditEditorHeightChange); used so the editor expands with content.
    var editEditorHeight: CGFloat = 36
    var onEditEditorHeightChange: ((CGFloat) -> Void)? = nil

    private var isProcessing: Bool { agentTaskState == .processing }
    private var isStopped: Bool { agentTaskState == .stopped }
    private var canOpenLinkedAgent: Bool { agentTaskState != .none }
    private var canDelegate: Bool { task.taskState == .inProgress && agentTaskState == .none }
    /// Only tasks in the Todo section (in progress with no linked agent or agent in todo state) are editable.
    private var canEdit: Bool {
        !task.completed && task.taskState == .inProgress && (agentTaskState == .none || agentTaskState == .todo)
    }
    /// When true, show model picker; when false, show read-only chip (no dropdown).
    private var canEditAgentModel: Bool { !isProcessing && !isStopped }
    private var firstScreenshotPath: String? { task.screenshotPaths.first }
    private var hasScreenshotSummary: Bool { !isEditing && firstScreenshotPath != nil }
    private var trailingContentReservedWidth: CGFloat {
        hasScreenshotSummary ? 92 : 40
    }
    private var selectedModel: ModelOption {
        models.first { $0.id == task.modelId }
            ?? AgentProviders.fallbackModels(for: task.providerID).first
            ?? ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
    }
    @State private var focusEditor: (() -> Void)?

    /// Trailing menu shown in an overlay so it sits exactly halfway down the card.
    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: CursorTheme.spaceS) {
            if let firstScreenshotPath, !isEditing {
                TaskScreenshotSummaryView(
                    workspacePath: workspacePath,
                    screenshotPath: firstScreenshotPath,
                    screenshotCount: task.screenshotPaths.count,
                    thumbnailSize: Self.compactScreenshotSize,
                    onOpenPreview: {
                        onPreviewScreenshot?(task.screenshotPaths, firstScreenshotPath, onDeleteScreenshot)
                    }
                )
            }

            if isProcessing, let onStopAgent {
                Menu {
                    Button("Review", systemImage: "person") {
                        onTap()
                    }
                    Button("Stop", systemImage: "stop.fill") {
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
                        Button("Review", systemImage: "person") {
                            onTap()
                        }
                        if let onContinueAgent {
                            Button("Continue", systemImage: "play.fill") {
                                onContinueAgent()
                            }
                        }
                        if let onResetAgent {
                            Button("Reset agent", systemImage: "arrow.counterclockwise") {
                                onResetAgent()
                            }
                        }
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
                    }
                    Button(task.completed ? "Mark as not done" : "Complete", systemImage: task.completed ? "circle" : "checkmark.circle") {
                        onToggleComplete()
                    }
                    Divider()
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
    }

    var body: some View {
        HStack(alignment: .top, spacing: CursorTheme.spaceS) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                if isEditing && !task.completed {
                    SubmittableTextEditor(
                        text: $editDraft,
                        isDisabled: false,
                        onSubmit: onCommitEdit,
                        onPasteImage: onPasteEditScreenshot,
                        onHeightChange: { onEditEditorHeightChange?($0) },
                        onFocusRequested: { focus, _ in
                            focusEditor = focus
                            if isEditing {
                                DispatchQueue.main.async {
                                    focus()
                                }
                            }
                        },
                        colorScheme: colorScheme,
                        font: NSFont.systemFont(ofSize: 14, weight: .regular),
                        textContainerInset: NSSize(width: 0, height: 4)
                    )
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: min(400, max(36, editEditorHeight)))
                        .onKeyPress(.escape) {
                            onCancelEdit()
                            return .handled
                        }
                    if !editScreenshots.isEmpty {
                        HStack(alignment: .center, spacing: 6) {
                            ForEach(editScreenshots) { item in
                                ScreenshotThumbnailView(
                                    image: item.image,
                                    size: CGSize(width: 56, height: 56),
                                    cornerRadius: 6,
                                    onTapPreview: { onPreviewEditScreenshot?(item.image) },
                                    onDelete: {
                                        onRemoveEditScreenshot?(item.id)
                                    }
                                )
                            }
                        }
                        .padding(.top, CursorTheme.spaceXS)
                    }
                    if !models.isEmpty {
                        Group {
                            if canEditAgentModel {
                                ModelPickerView(
                                    selectedModelId: task.modelId,
                                    models: models,
                                    onSelect: { onModelChange?($0) }
                                )
                            } else {
                                ModelChipView(model: selectedModel)
                            }
                        }
                        .padding(.top, CursorTheme.spaceS)
                    }
                } else {
                    // Task text only; screenshot strip and menu are in trailing overlay (vertically centered)
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
                        .onTapGesture(count: 2) { if !task.completed { onTap() } }
                }
                if !task.completed, !models.isEmpty, !isEditing {
                    Group {
                        if canEditAgentModel {
                            ModelPickerView(
                                selectedModelId: task.modelId,
                                models: models,
                                onSelect: { onModelChange?($0) }
                            )
                        } else {
                            ModelChipView(model: selectedModel)
                        }
                    }
                    .padding(.top, CursorTheme.spaceS)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, trailingContentReservedWidth)
        }
        .padding(CursorTheme.paddingCard)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .overlay(alignment: .trailing) {
            trailingControls
                .padding(.trailing, CursorTheme.paddingCard)
        }
        .contextMenu {
            if canOpenLinkedAgent {
                Button("Review", systemImage: "person") {
                    onTap()
                }
                if let onContinueAgent {
                    Button("Continue", systemImage: "play.fill") {
                        onContinueAgent()
                    }
                }
                if let onResetAgent {
                    Button("Reset agent", systemImage: "arrow.counterclockwise") {
                        onResetAgent()
                    }
                }
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
            }
            Button(task.completed ? "Mark as not done" : "Complete", systemImage: task.completed ? "circle" : "checkmark.circle") {
                onToggleComplete()
            }
            .disabled(isProcessing)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
            .disabled(isProcessing)
        }
        .onChange(of: isEditing) { _, editing in
            guard editing else { return }
            DispatchQueue.main.async {
                focusEditor?()
            }
        }
    }

}

#if DEBUG
private struct TasksPreviewWorkspace {
    let path: String
    let linkedStatuses: [UUID: AgentTaskState]
    let editableTask: ProjectTask
    let multiScreenshotTask: ProjectTask
    let singleScreenshotTask: ProjectTask
    let plainTask: ProjectTask
}

private enum TasksStorybookData {
    static let models: [ModelOption] = [
        ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false),
        ModelOption(id: "gpt-5.4-medium", label: "GPT-5.4", isPremium: true),
        ModelOption(id: "composer-1.5", label: "Composer 1.5", isPremium: true)
    ]

    static let workspace: TasksPreviewWorkspace = makeWorkspace()

    static func makeDraftScreenshots() -> [DraftTaskScreenshot] {
        [
            draftScreenshot(color: .systemRed),
            draftScreenshot(color: .systemOrange),
            draftScreenshot(color: .systemBlue)
        ].compactMap { $0 }
    }

    private static func makeWorkspace() -> TasksPreviewWorkspace {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorMetroTaskPreviews-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let todo = ProjectTasksStorage.addTask(
            workspacePath: workspaceURL.path,
            content: "Audit the spacing and hierarchy in the account settings screen.",
            screenshotData: [makePNGData(color: .systemRed), makePNGData(color: .systemOrange)].compactMap { $0 },
            providerID: .cursor,
            modelId: AvailableModels.autoID,
            taskState: .inProgress
        )
        let processing = ProjectTasksStorage.addTask(
            workspacePath: workspaceURL.path,
            content: "Check the startup logs and verify the preview server is healthy.",
            screenshotData: [],
            providerID: .cursor,
            modelId: AvailableModels.autoID,
            taskState: .inProgress
        )
        let review = ProjectTasksStorage.addTask(
            workspacePath: workspaceURL.path,
            content: "Confirm that the new onboarding panel matches the approved mock.",
            screenshotData: [makePNGData(color: .systemBlue)].compactMap { $0 },
            providerID: .cursor,
            modelId: "gpt-5.4-medium",
            taskState: .inProgress
        )
        let stopped = ProjectTasksStorage.addTask(
            workspacePath: workspaceURL.path,
            content: "Investigate why pasted screenshots are not appearing in the delegated prompt.",
            screenshotData: [],
            providerID: .cursor,
            modelId: "composer-1.5",
            taskState: .inProgress
        )
        _ = ProjectTasksStorage.addTask(
            workspacePath: workspaceURL.path,
            content: "Backlog: design a cleaner screenshot gallery for task cards.",
            screenshotData: [makePNGData(color: .systemPurple)].compactMap { $0 },
            providerID: .cursor,
            modelId: AvailableModels.autoID,
            taskState: .backlog
        )

        return TasksPreviewWorkspace(
            path: workspaceURL.path,
            linkedStatuses: [
                processing.id: .processing,
                review.id: .review,
                stopped.id: .stopped
            ],
            editableTask: todo,
            multiScreenshotTask: todo,
            singleScreenshotTask: review,
            plainTask: processing
        )
    }

    private static func draftScreenshot(color: NSColor) -> DraftTaskScreenshot? {
        guard let pngData = makePNGData(color: color) else { return nil }
        return DraftTaskScreenshot(pngData: pngData)
    }

    private static func makePNGData(color: NSColor) -> Data? {
        let size = CGSize(width: 80, height: 80)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 16, yRadius: 16).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct AddTaskStoryPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = "Capture the visual issues shown in the screenshots and outline the fixes."
    @State private var screenshots = TasksStorybookData.makeDraftScreenshots()
    @State private var selectedModelId = AvailableModels.autoID
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
            Text("Add Task Story")
                .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))

            VStack(alignment: .leading, spacing: CursorTheme.spaceS + CursorTheme.spaceXXS) {
                HStack(alignment: .top, spacing: CursorTheme.spaceS + CursorTheme.spaceXXS) {
                    Image(systemName: "circle")
                        .font(.system(size: CursorTheme.fontIconList))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))

                    SubmittableTextEditor(
                        text: $draft,
                        isDisabled: false,
                        onSubmit: {},
                        onPasteImage: nil,
                        colorScheme: colorScheme,
                        font: NSFont.systemFont(ofSize: CursorTheme.fontBody, weight: .regular),
                        textContainerInset: NSSize(width: 0, height: 4)
                    )
                    .frame(minHeight: 48, maxHeight: 140)

                    Button(action: {}) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }

                if !screenshots.isEmpty {
                    HStack(alignment: .center, spacing: CursorTheme.spaceS) {
                        ForEach(screenshots) { item in
                            ScreenshotThumbnailView(
                                image: item.image,
                                size: CGSize(width: 56, height: 56),
                                cornerRadius: 6,
                                onTapPreview: { previewImage = item.image },
                                onDelete: {
                                    if previewImage === item.image {
                                        previewImage = nil
                                    }
                                    screenshots.removeAll { $0.id == item.id }
                                }
                            )
                        }
                    }
                }

                ModelPickerView(
                    selectedModelId: selectedModelId,
                    models: TasksStorybookData.models,
                    onSelect: { selectedModelId = $0 }
                )
            }
            .padding(CursorTheme.paddingCard)
            .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )
        }
        .padding(CursorTheme.paddingPanel)
        .frame(width: 760)
        .background(CursorTheme.panel(for: colorScheme))
    }
}

private struct EditTaskStoryPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var editDraft = "Audit the spacing and hierarchy in the account settings screen."
    @State private var editScreenshots = TasksStorybookData.makeDraftScreenshots()

    var body: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
            Text("Edit Task Story")
                .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))

            TaskRowView(
                task: TasksStorybookData.workspace.editableTask,
                workspacePath: TasksStorybookData.workspace.path,
                models: TasksStorybookData.models,
                agentTaskState: .none,
                isEditing: true,
                editDraft: $editDraft,
                editScreenshots: editScreenshots,
                onTap: {},
                onCommitEdit: {},
                onCancelEdit: {},
                onToggleComplete: {},
                onSendToAgent: {},
                onDelete: {},
                onPreviewEditScreenshot: { _ in },
                onRemoveEditScreenshot: { id in
                    editScreenshots.removeAll { $0.id == id }
                }
            )
        }
        .padding(CursorTheme.paddingPanel)
        .frame(width: 760)
        .background(CursorTheme.panel(for: colorScheme))
    }
}

private struct TaskRowScreenshotStatesPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var editDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
            Text("Task Row Screenshot States")
                .font(.system(size: CursorTheme.fontTitle, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))

            TaskRowView(
                task: TasksStorybookData.workspace.multiScreenshotTask,
                workspacePath: TasksStorybookData.workspace.path,
                models: TasksStorybookData.models,
                agentTaskState: .none,
                isEditing: false,
                editDraft: $editDraft,
                onTap: {},
                onCommitEdit: {},
                onCancelEdit: {},
                onToggleComplete: {},
                onSendToAgent: {},
                onDelete: {}
            )

            TaskRowView(
                task: TasksStorybookData.workspace.singleScreenshotTask,
                workspacePath: TasksStorybookData.workspace.path,
                models: TasksStorybookData.models,
                agentTaskState: .none,
                isEditing: false,
                editDraft: $editDraft,
                onTap: {},
                onCommitEdit: {},
                onCancelEdit: {},
                onToggleComplete: {},
                onSendToAgent: {},
                onDelete: {}
            )

            TaskRowView(
                task: TasksStorybookData.workspace.plainTask,
                workspacePath: TasksStorybookData.workspace.path,
                models: TasksStorybookData.models,
                agentTaskState: .none,
                isEditing: false,
                editDraft: $editDraft,
                onTap: {},
                onCommitEdit: {},
                onCancelEdit: {},
                onToggleComplete: {},
                onSendToAgent: {},
                onDelete: {}
            )
        }
        .padding(CursorTheme.paddingPanel)
        .frame(width: 760)
        .background(CursorTheme.panel(for: colorScheme))
    }
}

#Preview("Tasks – Full List Stories") {
    TasksListView(
        workspacePath: TasksStorybookData.workspace.path,
        triggerAddNewTask: .constant(false),
        linkedStatuses: TasksStorybookData.workspace.linkedStatuses,
        newTaskProviderID: .cursor,
        modelsForProvider: { _ in TasksStorybookData.models },
        onSendToAgent: { _, _, _, _, _ in },
        onOpenLinkedAgent: { _ in },
        onContinueAgent: { _ in },
        onResetAgent: { _ in },
        onStopAgent: { _ in },
        onTasksDidUpdate: {},
        onDismiss: {}
    )
    .frame(width: 900, height: 720)
    .preferredColorScheme(.dark)
}

#Preview("Tasks – Add With Screenshots") {
    AddTaskStoryPreview()
        .preferredColorScheme(.dark)
}

#Preview("Tasks – Edit With Screenshots") {
    EditTaskStoryPreview()
        .preferredColorScheme(.dark)
}

#Preview("Tasks – Task Rows With And Without Screenshots") {
    TaskRowScreenshotStatesPreview()
        .preferredColorScheme(.dark)
}
#endif
