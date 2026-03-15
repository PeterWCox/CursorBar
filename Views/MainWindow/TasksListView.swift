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

private struct SectionScopedTaskRow: Identifiable, Equatable {
    let sectionID: String
    let task: ProjectTask

    var id: String {
        "\(sectionID)-\(task.id.uuidString)"
    }
}

private struct TasksTabCounts: Equatable {
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

/// One time-bucket group (title + tasks) for Equatable snapshot.
private struct TimeBucketGroup: Equatable {
    let title: String
    let tasks: [ProjectTask]
}

/// Time-based section for Completed and Deleted tabs (Today, Yesterday, Last 7 Days, etc.).
private enum TimeBucket: Int, CaseIterable {
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

private struct TasksListSnapshot: Equatable {
    let backlogTasks: [ProjectTask]
    let reviewRows: [SectionScopedTaskRow]
    let stoppedRows: [SectionScopedTaskRow]
    let processingRows: [SectionScopedTaskRow]
    let todoRows: [SectionScopedTaskRow]
    let visibleCompletedTasks: [ProjectTask]
    /// Completed tasks grouped by time bucket (Today, Yesterday, …), ordered newest first.
    let completedGrouped: [TimeBucketGroup]
    let deletedTasks: [ProjectTask]
    /// Deleted tasks grouped by time bucket, ordered newest first.
    let deletedGrouped: [TimeBucketGroup]
    let counts: TasksTabCounts
}

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
    /// True when Start Preview opened an external terminal window; Stop closes it.
    @State private var previewRunningInExternalTerminal: Bool = false

    private static let completedRecentInterval: TimeInterval = 24 * 60 * 60

    private var preferredTerminal: PreferredTerminalApp {
        PreferredTerminalApp(rawValue: preferredTerminalAppRawValue) ?? .automatic
    }

    private func reloadTasks() {
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
        deletedTasksList = ProjectTasksStorage.deletedTasks(workspacePath: workspacePath)
    }

    private func hangDiagnosticsSnapshot() -> [String: String] {
        let snapshot = taskSnapshot
        return [
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

    private func updateHangDiagnosticsSnapshot() {
        HangDiagnostics.shared.updateSnapshot(hangDiagnosticsSnapshot())
    }

    private func recordHangEvent(_ event: String, metadata: [String: String] = [:]) {
        updateHangDiagnosticsSnapshot()
        HangDiagnostics.shared.record(event, metadata: metadata)
    }

    private var taskSnapshot: TasksListSnapshot {
        makeSnapshot()
    }

    private func makeSnapshot(referenceDate: Date = Date()) -> TasksListSnapshot {
        let backlogTasks = tasks.filter { $0.taskState == .backlog }
        let inProgressTasks = tasks.filter { $0.taskState == .inProgress }
        let completedTasks = tasks.filter { $0.taskState == .completed }
        let reviewTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .review }
        let stoppedTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .stopped }
        let processingTasks = inProgressTasks.filter { linkedStatuses[$0.id] == .processing }
        let todoTasks = inProgressTasks.filter {
            let state = linkedStatuses[$0.id]
            return state == nil || state == AgentTaskState.none || state == .todo
        }
        let cutoff = referenceDate.addingTimeInterval(-Self.completedRecentInterval)
        let visibleCompletedTasks = showOnlyRecentCompleted
            ? completedTasks.filter { ($0.completedAt ?? .distantPast) >= cutoff }
            : completedTasks
        let sortedVisibleCompletedTasks = visibleCompletedTasks
            .sorted { ($0.completedAt ?? .distantPast) >= ($1.completedAt ?? .distantPast) }

        let completedGrouped = Self.groupTasksByTimeBucket(
            sortedVisibleCompletedTasks,
            dateKeyPath: \.completedAt,
            reference: referenceDate
        )
        let deletedGrouped = Self.groupTasksByTimeBucket(
            deletedTasksList,
            dateKeyPath: \.deletedAt,
            reference: referenceDate
        )

        return TasksListSnapshot(
            backlogTasks: backlogTasks,
            reviewRows: reviewTasks.map { SectionScopedTaskRow(sectionID: "Review", task: $0) },
            stoppedRows: stoppedTasks.map { SectionScopedTaskRow(sectionID: "Stopped", task: $0) },
            processingRows: processingTasks.map { SectionScopedTaskRow(sectionID: "Processing", task: $0) },
            todoRows: todoTasks.map { SectionScopedTaskRow(sectionID: "Todo", task: $0) },
            visibleCompletedTasks: sortedVisibleCompletedTasks,
            completedGrouped: completedGrouped,
            deletedTasks: deletedTasksList,
            deletedGrouped: deletedGrouped,
            counts: TasksTabCounts(
                backlog: backlogTasks.count,
                inProgress: inProgressTasks.count,
                completed: completedTasks.count,
                deleted: deletedTasksList.count
            )
        )
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

    private func commitNewTask() {
        let trimmed = newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            recordHangEvent("tasks-commit-new-task", metadata: [
                "contentLength": "\(trimmed.count)",
                "screenshots": "\(newTaskDraftScreenshots.count)"
            ])
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
        recordHangEvent("tasks-cancel-new-task")
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
        recordHangEvent("tasks-select-tab", metadata: [
            "from": selectedTasksTab.rawValue,
            "to": tab.rawValue
        ])
        if tab != .inProgress && tab != .backlog && isAddingNewTask {
            cancelNewTask()
        }
        selectedTasksTab = tab
    }

    var body: some View {
        let snapshot = taskSnapshot
        VStack(spacing: 0) {
            if showHeader { header }
            TasksTabBarView(
                selectedTab: selectedTasksTab,
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
                            .id(selectedTasksTab)
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
            updateHangDiagnosticsSnapshot()
            // Handle Cmd+T when it fired before this view was in the hierarchy (trigger already true).
            if triggerAddNewTask.wrappedValue {
                showNewTaskComposer(selecting: .inProgress)
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: workspacePath) { _, _ in reloadTasks() }
        .onChange(of: selectedTasksTab) { _, _ in updateHangDiagnosticsSnapshot() }
        .onChange(of: tasks) { _, _ in updateHangDiagnosticsSnapshot() }
        .onChange(of: deletedTasksList) { _, _ in updateHangDiagnosticsSnapshot() }
        .onChange(of: linkedStatuses) { _, _ in updateHangDiagnosticsSnapshot() }
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

    @ViewBuilder
    private func tabContent(snapshot: TasksListSnapshot) -> some View {
        switch selectedTasksTab {
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
        let isEmpty = snapshot.counts.inProgress == 0 && !isAddingNewTask
        if isEmpty {
            emptyStateInProgress
        } else {
            if isAddingNewTask {
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

    /// Start Preview / Stop / Open in Browser / Configure Setup (external terminal; window closes on Stop).
    private var previewButtonsBar: some View {
        let debugURL = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) ?? ""
        let startupContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? ""
        let isConfigured = !startupContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPreviewURL = !debugURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: CursorTheme.spaceS) {
            addTaskChip
            Spacer(minLength: 0)
            if previewRunningInExternalTerminal {
                ActionButton(
                    title: "Stop",
                    icon: "stop.fill",
                    action: {
                        _ = closePreviewTerminalWindow(workspacePath: workspacePath)
                        previewRunningInExternalTerminal = false
                    },
                    help: "Close the preview terminal window",
                    style: .stop
                )
                if hasPreviewURL {
                    ActionButton(
                        title: "Open in Browser",
                        icon: "safari",
                        action: {
                            guard let url = URL(string: debugURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                            openURLInChrome(url)
                        },
                        help: "Open the preview URL in Chrome",
                        style: .primary
                    )
                }
            } else {
                if isConfigured {
                    ActionButton(
                        title: "Start Preview",
                        icon: "play.fill",
                        action: {
                            if launchStartupScriptInNewWindow(workspacePath: workspacePath, preferredTerminal: preferredTerminal) == nil {
                                previewRunningInExternalTerminal = true
                            }
                        },
                        help: "Run .metro/startup.sh in a new terminal window (closed when you tap Stop)",
                        style: .play
                    )
                }
                if let launch = onLaunchSetupAgent {
                    ActionButton(
                        title: isConfigured ? "Regenerate Setup" : "Configure Setup",
                        icon: "gearshape",
                        action: { launch(workspacePath) },
                        help: isConfigured ? "Launch an agent to regenerate .metro/startup.sh and debug URL" : "Launch an agent to set up .metro/startup.sh and debug URL for this project",
                        style: .accent
                    )
                }
            }
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
        let isEmpty = snapshot.backlogTasks.isEmpty && !isAddingNewTask
        if isEmpty {
            emptyStateBacklog
        } else {
            if isAddingNewTask {
                newTaskRow
            }
            ForEach(snapshot.backlogTasks) { task in
                taskRow(task, stateTransitionLabel: "Move to In Progress", stateTransitionIcon: "arrow.right.circle", onStateTransition: {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, taskState: .inProgress)
                    reloadTasks()
                })
            }
        }
    }

    @ViewBuilder
    private func completedContent(snapshot: TasksListSnapshot) -> some View {
        if snapshot.visibleCompletedTasks.isEmpty {
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
            ForEach(Array(snapshot.completedGrouped.enumerated()), id: \.offset) { _, group in
                timeBucketSection(title: group.title, tasks: group.tasks) { taskRow($0) }
            }
        }
    }

    @ViewBuilder
    private func deletedContent(snapshot: TasksListSnapshot) -> some View {
        if snapshot.deletedTasks.isEmpty {
            emptyStateDeleted
        } else {
            ForEach(Array(snapshot.deletedGrouped.enumerated()), id: \.offset) { _, group in
                timeBucketSection(title: group.title, tasks: group.tasks) { deletedTaskRow($0) }
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
            onContinueAgent: linkedStatuses[task.id] == .stopped ? { onContinueAgent(task) } : nil,
            onResetAgent: linkedStatuses[task.id] == .stopped ? { onResetAgent(task) } : nil
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
                        Text("Add task…")
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
    /// When non-nil (processing tasks), the row shows a 3-dot menu with a single "Stop" item.
    var onStopAgent: (() -> Void)? = nil
    /// When non-nil (stopped tasks), the row shows "Continue" which focuses the agent and sends "continue".
    var onContinueAgent: (() -> Void)? = nil
    /// When non-nil (stopped tasks), the row shows "Reset agent" which closes the linked agent and starts a fresh one.
    var onResetAgent: (() -> Void)? = nil

    private var isProcessing: Bool { agentTaskState == .processing }
    private var isStopped: Bool { agentTaskState == .stopped }
    private var canOpenLinkedAgent: Bool { agentTaskState != .none }
    private var canDelegate: Bool { task.taskState == .inProgress && agentTaskState == .none }
    /// Stopped agents are not editable; only non-completed, non-processing, non-stopped tasks can be edited.
    private var canEdit: Bool { !task.completed && !isProcessing && !isStopped }
    /// When true, show model picker; when false, show read-only chip (no dropdown).
    private var canEditAgentModel: Bool { !isProcessing && !isStopped }
    private var selectedModel: ModelOption {
        models.first { $0.id == task.modelId } ?? ModelOption(id: AvailableModels.autoID, label: "Auto", isPremium: false)
    }

    /// Trailing controls (screenshot strip + 3-dot menu) shown in an overlay so they sit exactly halfway down the card.
    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: CursorTheme.spaceS) {
            if !task.screenshotPaths.isEmpty {
                TaskScreenshotStripView(
                    workspacePath: workspacePath,
                    paths: task.screenshotPaths,
                    onPreview: { onPreviewScreenshot?($0) },
                    onDelete: onDeleteScreenshot
                )
            }
            if isProcessing, let onStopAgent {
                Menu {
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
                        Button("Open linked Agent", systemImage: "arrow.up.right") {
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
    }

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
                        .onTapGesture(count: 2) { if !task.completed, !isProcessing { onTap() } }
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
            .padding(.trailing, 88)
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
                Button("Open linked Agent", systemImage: "arrow.up.right") {
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
