import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tasks (todos) list for a project

struct TasksListView: View {
    let workspacePath: String
    /// When set to true from outside (e.g. Cmd+T), show the add-new-task row and focus it.
    var triggerAddNewTask: Binding<Bool> = .constant(false)
    /// Send task content to a new agent; when taskID is non-nil, the new agent is linked to that task.
    var onSendToAgent: (String, UUID?) -> Void
    var onDismiss: () -> Void
    /// Agents for this workspace (for "Link to Agent" menu).
    var agentsForWorkspace: [AgentTab] = []
    var isTaskLinked: (UUID) -> Bool = { _ in false }
    /// Status of the linked agent for each task (open / processing / done); shown on the task row.
    var linkedTaskStatusForTaskID: (UUID) -> LinkedTaskStatus? = { _ in nil }
    var onLinkTaskToAgent: (ProjectTask, AgentTab) -> Void = { _, _ in }
    var onUnlinkTask: (UUID) -> Void = { _ in }

    @State private var tasks: [ProjectTask] = []
    @State private var editingTask: ProjectTask?
    @State private var editingDraft: String = ""
    @State private var isAddingNewTask: Bool = false
    @State private var newTaskDraft: String = ""
    @State private var newTaskScreenshot: NSImage? = nil
    @State private var showScreenshotFileImporter: Bool = false
    @FocusState private var isNewTaskFieldFocused: Bool
    @FocusState private var isTaskEditorFocused: Bool
    /// When true, show only archived tasks completed in the last 24 hours. When false, show all archived.
    @State private var showOnlyRecentArchived: Bool = true
    /// Collapsed state for Todo and Archived sections (false = expanded).
    @State private var todoSectionCollapsed: Bool = false
    @State private var archivedSectionCollapsed: Bool = false
    /// When adding a new task, Cmd+V pastes screenshot from clipboard. Monitor is installed only while the new-task row is visible.
    @State private var newTaskPasteKeyMonitor: Any?
    /// URL for full-screen task screenshot preview (same pattern as PopoutView screenshot preview).
    @State private var taskScreenshotPreviewURL: URL? = nil

    private static let archivedRecentInterval: TimeInterval = 24 * 60 * 60

    private func reloadTasks() {
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
    }

    /// Sort order for todo list: no status first, then done, then processing, then open (stopped after done).
    private func linkedStatusSortOrder(_ status: LinkedTaskStatus?) -> Int {
        switch status {
        case nil: return 0
        case .done: return 1
        case .stopped: return 2
        case .processing: return 3
        case .open: return 4
        }
    }

    private var todoTasks: [ProjectTask] {
        tasks
            .filter { !$0.completed }
            .sorted { linkedStatusSortOrder(linkedTaskStatusForTaskID($0.id)) < linkedStatusSortOrder(linkedTaskStatusForTaskID($1.id)) }
    }

    private var archivedTasks: [ProjectTask] {
        tasks.filter(\.completed)
    }

    private var visibleArchivedTasks: [ProjectTask] {
        let cutoff = Date().addingTimeInterval(-Self.archivedRecentInterval)
        let filtered = showOnlyRecentArchived
            ? archivedTasks.filter { ($0.completedAt ?? .distantPast) >= cutoff }
            : archivedTasks
        return filtered.sorted { ($0.completedAt ?? .distantPast) >= ($1.completedAt ?? .distantPast) }
    }

    private func commitNewTask() {
        let trimmed = newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            _ = ProjectTasksStorage.addTask(workspacePath: workspacePath, content: trimmed, screenshotImage: newTaskScreenshot)
            reloadTasks()
            newTaskDraft = ""
            newTaskScreenshot = nil
        }
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    private func cancelNewTask() {
        newTaskDraft = ""
        newTaskScreenshot = nil
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border)
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if todoTasks.isEmpty && visibleArchivedTasks.isEmpty && !isAddingNewTask {
                        emptyState
                    } else {
                        if isAddingNewTask {
                            newTaskRow
                        }
                        // Todo section
                        if !todoTasks.isEmpty {
                            sectionHeader("Todo", showFilter: false, isCollapsed: todoSectionCollapsed) {
                                todoSectionCollapsed.toggle()
                            }
                            if !todoSectionCollapsed {
                                ForEach(todoTasks) { task in
                                    taskRow(task)
                                }
                            }
                        }
                        // Archived section (done tasks)
                        if !archivedTasks.isEmpty {
                            sectionHeader("Archived", showFilter: true, isCollapsed: archivedSectionCollapsed) {
                                archivedSectionCollapsed.toggle()
                            } onFilterToggle: {
                                showOnlyRecentArchived.toggle()
                            }
                            if !archivedSectionCollapsed {
                                ForEach(visibleArchivedTasks) { task in
                                    taskRow(task)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { reloadTasks() }
        .onChange(of: workspacePath) { _, _ in reloadTasks() }
        .onChange(of: triggerAddNewTask.wrappedValue) { _, requested in
            if requested {
                isAddingNewTask = true
                triggerAddNewTask.wrappedValue = false
            }
        }
        .onChange(of: isAddingNewTask) { _, showing in
            if showing {
                isNewTaskFieldFocused = true
                // Intercept Cmd+V so pasting an image attaches it as the task screenshot instead of into the text field.
                newTaskPasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCommandV = modifiers.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
                    if isCommandV, SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) != nil {
                        if let img = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                            newTaskScreenshot = img
                        }
                        return nil
                    }
                    return event
                }
            } else {
                if let monitor = newTaskPasteKeyMonitor {
                    NSEvent.removeMonitor(monitor)
                    newTaskPasteKeyMonitor = nil
                }
            }
        }
        .onChange(of: editingTask) { _, new in
            if new != nil { isTaskEditorFocused = true }
        }
        .overlay {
            if let url = taskScreenshotPreviewURL {
                ScreenshotPreviewModal(imageURL: url, isPresented: Binding(
                    get: { true },
                    set: { if !$0 { taskScreenshotPreviewURL = nil } }
                ))
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(
        _ title: String,
        showFilter: Bool = false,
        isCollapsed: Bool = false,
        onCollapseToggle: (() -> Void)? = nil,
        onFilterToggle: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: { onCollapseToggle?() }) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .frame(width: 14, height: 14)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showFilter, let onFilterToggle {
                Button(action: onFilterToggle) {
                    Text(showOnlyRecentArchived ? "Show all" : "Last 24 hours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CursorTheme.brandBlue)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
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
    private func taskRow(_ task: ProjectTask) -> some View {
        TaskRowView(
            task: task,
            workspacePath: workspacePath,
            isLinked: isTaskLinked(task.id),
            linkedTaskStatus: linkedTaskStatusForTaskID(task.id),
            agentsForWorkspace: agentsForWorkspace,
            isEditing: editingTask?.id == task.id,
            editDraft: $editingDraft,
            isEditorFocused: $isTaskEditorFocused,
            onTap: {
                editingDraft = task.content
                editingTask = task
            },
            onCommitEdit: commitEdit,
            onCancelEdit: { editingTask = nil },
            onToggleComplete: {
                ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, completed: !task.completed)
                reloadTasks()
            },
            onSendToAgent: { onSendToAgent(task.content, task.id) },
            onLinkToAgent: { agent in onLinkTaskToAgent(task, agent) },
            onUnlink: { onUnlinkTask(task.id) },
            onDelete: {
                ProjectTasksStorage.deleteTask(workspacePath: workspacePath, id: task.id)
                reloadTasks()
            },
            onPreviewScreenshot: task.screenshotPath != nil ? {
                taskScreenshotPreviewURL = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: task.screenshotPath!)
            } : nil,
            onDeleteScreenshot: (task.screenshotPath != nil && !task.completed) ? {
                ProjectTasksStorage.updateTaskScreenshot(workspacePath: workspacePath, id: task.id, image: nil)
                reloadTasks()
            } : nil
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)
                Text((workspacePath as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                newTaskDraft = ""
                isAddingNewTask = true
            }) {
                Label("New task", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(CursorTheme.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text("No tasks yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CursorTheme.textSecondary)
            Text("Add a task to track work for this project. You can send any task to a new agent tab.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(CursorTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(action: {
                newTaskDraft = ""
                isAddingNewTask = true
            }) {
                Label("New task", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(CursorTheme.brandBlue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var newTaskRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(CursorTheme.textTertiary)

                TextField("New task…", text: $newTaskDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .focused($isNewTaskFieldFocused)
                    .onSubmit { commitNewTask() }
                    .onKeyPress(.escape) {
                        cancelNewTask()
                        return .handled
                    }

                Button(action: cancelNewTask) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CursorTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            TaskScreenshotDraftView(
                image: $newTaskScreenshot,
                showFileImporter: $showScreenshotFileImporter,
                thumbnailSize: CGSize(width: 72, height: 72)
            )
        }
        .padding(12)
        .background(CursorTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
        .fileImporter(
            isPresented: $showScreenshotFileImporter,
            allowedContentTypes: [.image, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let image = NSImage(contentsOf: url) {
                newTaskScreenshot = image
            }
        }
    }

    @ViewBuilder
    private func editTaskSheet(task: ProjectTask) -> some View {
        EditTaskSheet(
            workspacePath: workspacePath,
            taskId: task.id,
            initialContent: task.content,
            initialScreenshotPath: task.screenshotPath,
            onSave: { newContent in
                let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, content: trimmed)
                    reloadTasks()
                }
                editingTask = nil
            },
            onCancel: { editingTask = nil }
        )
    }
}

// MARK: - Task status badge (open / processing / done / stopped)

private struct TaskStatusBadge: View {
    let status: LinkedTaskStatus

    private var display: (icon: String, color: Color, label: String) {
        switch status {
        case .open:
            return ("circle", CursorTheme.textTertiary, "open")
        case .processing:
            return ("arrow.trianglehead.2.clockwise.rotate.90", CursorTheme.brandBlue, "processing")
        case .done:
            return ("checkmark.circle.fill", Color.green, "done")
        case .stopped:
            return ("stop.fill", Color.red, "stopped")
        }
    }

    var body: some View {
        let (icon, color, label) = display
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Task screenshot thumbnail (in todo row): tappable preview + delete

private struct TaskScreenshotThumbnailView: View {
    let workspacePath: String
    let screenshotPath: String
    var onTapPreview: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var imageURL: URL {
        ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
    }

    /// Small "expand" icon overlay (matches ScreenshotCardView affordance).
    private var expandPreviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    var body: some View {
        if let nsImage = NSImage(contentsOf: imageURL) {
            HStack(alignment: .center, spacing: 6) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                    .overlay(expandPreviewOverlay)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapPreview?()
                    }

                if onDelete != nil {
                    Button(action: { onDelete?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(CursorTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    let task: ProjectTask
    let workspacePath: String
    let isLinked: Bool
    var linkedTaskStatus: LinkedTaskStatus? = nil
    let agentsForWorkspace: [AgentTab]
    var isEditing: Bool = false
    @Binding var editDraft: String
    var isEditorFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onToggleComplete: () -> Void
    let onSendToAgent: () -> Void
    let onLinkToAgent: (AgentTab) -> Void
    let onUnlink: () -> Void
    let onDelete: () -> Void
    var onPreviewScreenshot: (() -> Void)? = nil
    var onDeleteScreenshot: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.completed ? CursorTheme.brandBlue : CursorTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(isEditing)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing && !task.completed {
                    TextEditor(text: $editDraft)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 24, maxHeight: 120)
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
                } else {
                    Text(task.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(task.completed ? CursorTheme.textTertiary : CursorTheme.textPrimary)
                        .strikethrough(task.completed)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if !task.completed { onTap() } }
                }
                if let path = task.screenshotPath {
                    TaskScreenshotThumbnailView(
                        workspacePath: workspacePath,
                        screenshotPath: path,
                        onTapPreview: onPreviewScreenshot,
                        onDelete: onDeleteScreenshot
                    )
                }
                if let status = linkedTaskStatus {
                    TaskStatusBadge(status: status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(task.completed ? "Mark as not done" : "Mark as Done", systemImage: task.completed ? "circle" : "checkmark.circle") {
                    onToggleComplete()
                }
                if !task.completed {
                    Divider()
                    Button("Send to new Agent", systemImage: "bubble.left.and.bubble.right") {
                        onSendToAgent()
                    }
                    if !agentsForWorkspace.isEmpty {
                        Menu("Link to Agent", systemImage: "link") {
                            ForEach(agentsForWorkspace) { agent in
                                Button(agent.title) {
                                    onLinkToAgent(agent)
                                }
                            }
                        }
                    }
                    if isLinked {
                        Button("Unlink from Agent", systemImage: "link.slash") {
                            onUnlink()
                        }
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(12)
        .background(CursorTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Screenshot draft (new task / edit): thumbnail or add controls

private struct TaskScreenshotDraftView: View {
    @Binding var image: NSImage?
    @Binding var showFileImporter: Bool
    var thumbnailSize: CGSize

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border, lineWidth: 1)
                    )
                Button(action: { image = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(CursorTheme.textTertiary)
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    Button("Paste from clipboard") {
                        if let pasted = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                            image = pasted
                        }
                    }
                    Button("Choose file…") {
                        showFileImporter = true
                    }
                } label: {
                    Label("Add screenshot", systemImage: "photo.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CursorTheme.brandBlue)
                }
                .menuStyle(.borderlessButton)
            }
        }
    }
}

// MARK: - Edit task sheet (content + optional screenshot)

private struct EditTaskSheet: View {
    let workspacePath: String
    let taskId: UUID
    let initialContent: String
    let initialScreenshotPath: String?
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var draft: String = ""
    @State private var draftScreenshotImage: NSImage? = nil
    @State private var screenshotRemoved: Bool = false
    @State private var showScreenshotFileImporter: Bool = false

    private var effectiveScreenshot: NSImage? {
        if screenshotRemoved { return nil }
        if let img = draftScreenshotImage { return img }
        guard let path = initialScreenshotPath else { return nil }
        let url = ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path)
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit task")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .foregroundStyle(CursorTheme.textSecondary)
                Button("Save") {
                    saveTask()
                }
                .fontWeight(.semibold)
                .foregroundStyle(CursorTheme.brandBlue)
            }
            .padding(16)
            Divider().background(CursorTheme.border)
            SubmittableTextEditor(
                text: $draft,
                isDisabled: false,
                onSubmit: { },
                onPasteImage: {
                    if let img = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                        draftScreenshotImage = img
                        screenshotRemoved = false
                    }
                }
            )
            .padding(12)
            .frame(minHeight: 140)
            Divider().background(CursorTheme.border)
            HStack(alignment: .center, spacing: 10) {
                Text("Screenshot")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary)
                editSheetScreenshotSection
            }
            .padding(12)
        }
        .frame(width: 440, height: 380)
        .background(CursorTheme.surface)
        .onAppear {
            draft = initialContent
            if initialScreenshotPath != nil { screenshotRemoved = false }
        }
        .fileImporter(
            isPresented: $showScreenshotFileImporter,
            allowedContentTypes: [.image, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let loaded = NSImage(contentsOf: url) {
                draftScreenshotImage = loaded
                screenshotRemoved = false
            }
        }
    }

    @ViewBuilder
    private var editSheetScreenshotSection: some View {
        if let img = effectiveScreenshot {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CursorTheme.border, lineWidth: 1)
                )
            Menu {
                Button("Replace with clipboard") {
                    if let pasted = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                        draftScreenshotImage = pasted
                        screenshotRemoved = false
                    }
                }
                Button("Replace with file…") {
                    showScreenshotFileImporter = true
                }
                Button("Remove screenshot", role: .destructive) {
                    draftScreenshotImage = nil
                    screenshotRemoved = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(CursorTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
        } else {
            Menu {
                Button("Paste from clipboard") {
                    if let pasted = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                        draftScreenshotImage = pasted
                        screenshotRemoved = false
                    }
                }
                Button("Choose file…") {
                    showScreenshotFileImporter = true
                }
            } label: {
                Label("Add screenshot", systemImage: "photo.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CursorTheme.brandBlue)
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func saveTask() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: taskId, content: trimmed)
        }
        if screenshotRemoved {
            ProjectTasksStorage.updateTaskScreenshot(workspacePath: workspacePath, id: taskId, image: nil)
        } else if let img = draftScreenshotImage {
            ProjectTasksStorage.updateTaskScreenshot(workspacePath: workspacePath, id: taskId, image: img)
        }
        onSave(draft)
    }
}
