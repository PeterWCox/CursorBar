import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Tasks (todos) list for a project

struct TasksListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    /// When set to true from outside (e.g. Cmd+T), show the add-new-task row and focus it.
    var triggerAddNewTask: Binding<Bool> = .constant(false)
    /// When set, returns the linked agent status for a task (open / processing / done / stopped) to show a badge on the task row.
    var linkedStatusForTaskID: ((UUID) -> LinkedTaskStatus?)? = nil
    /// Send task content to a new agent; when taskID is non-nil, the new agent is linked to that task. When screenshotPaths is non-empty, those paths (under .cursormetro) are attached to the prompt.
    var onSendToAgent: (String, UUID?, [String]) -> Void
    var onDismiss: () -> Void

    @State private var tasks: [ProjectTask] = []
    @State private var editingTask: ProjectTask?
    @State private var editingDraft: String = ""
    @State private var editingScreenshotImages: [NSImage] = []
    @State private var showEditScreenshotFileImporter: Bool = false
    @State private var isAddingNewTask: Bool = false
    @State private var newTaskDraft: String = ""
    @State private var newTaskScreenshots: [NSImage] = []
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
    /// When editing a task, Cmd+V pastes screenshot from clipboard.
    @State private var editTaskPasteKeyMonitor: Any?
    /// URL for full-screen task screenshot preview (same pattern as PopoutView screenshot preview).
    @State private var taskScreenshotPreviewURL: URL? = nil

    private static let archivedRecentInterval: TimeInterval = 24 * 60 * 60

    private func reloadTasks() {
        tasks = ProjectTasksStorage.tasks(workspacePath: workspacePath)
    }

    private var todoTasks: [ProjectTask] {
        tasks.filter { !$0.completed }
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
            _ = ProjectTasksStorage.addTask(workspacePath: workspacePath, content: trimmed, screenshotImages: newTaskScreenshots)
            reloadTasks()
            newTaskDraft = ""
            newTaskScreenshots = []
        }
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    private func cancelNewTask() {
        newTaskDraft = ""
        newTaskScreenshots = []
        isAddingNewTask = false
        isNewTaskFieldFocused = false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(CursorTheme.border(for: colorScheme))
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
                    if isCommandV, newTaskScreenshots.count < AppLimits.maxScreenshots,
                       let img = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                        newTaskScreenshots.append(img)
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
            if let task = new {
                isTaskEditorFocused = true
                editingScreenshotImages = task.screenshotPaths.compactMap { path in
                    NSImage(contentsOf: ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: path))
                }
                editTaskPasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCommandV = modifiers.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
                    if isCommandV, editingScreenshotImages.count < AppLimits.maxScreenshots,
                       let img = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                        editingScreenshotImages = editingScreenshotImages + [img]
                        return nil
                    }
                    return event
                }
            } else {
                editingScreenshotImages = []
                if let monitor = editTaskPasteKeyMonitor {
                    NSEvent.removeMonitor(monitor)
                    editTaskPasteKeyMonitor = nil
                }
            }
        }
        .overlay {
            if let url = taskScreenshotPreviewURL {
                ScreenshotPreviewModal(imageURL: url, isPresented: Binding(
                    get: { true },
                    set: { if !$0 { taskScreenshotPreviewURL = nil } }
                ))
            }
        }
        .fileImporter(
            isPresented: $showEditScreenshotFileImporter,
            allowedContentTypes: [.image, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            let toAdd = urls.prefix(AppLimits.maxScreenshots - editingScreenshotImages.count)
            for url in toAdd {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let image = NSImage(contentsOf: url) {
                    editingScreenshotImages.append(image)
                }
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
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .frame(width: 14, height: 14)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
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
            ProjectTasksStorage.updateTaskScreenshots(workspacePath: workspacePath, id: id, images: editingScreenshotImages)
            reloadTasks()
        }
        editingTask = nil
    }

    @ViewBuilder
    private func taskRow(_ task: ProjectTask) -> some View {
        TaskRowView(
            task: task,
            workspacePath: workspacePath,
            linkedTaskStatus: linkedStatusForTaskID?(task.id),
            isEditing: editingTask?.id == task.id,
            editDraft: $editingDraft,
            editScreenshotImages: $editingScreenshotImages,
            showEditScreenshotFileImporter: $showEditScreenshotFileImporter,
            isEditorFocused: $isTaskEditorFocused,
            onTap: {
                let content = task.content
                let taskToEdit = task
                // Defer so when triggered from context/menu the menu dismisses first and inline editor gets focus
                DispatchQueue.main.async {
                    editingDraft = content
                    editingTask = taskToEdit
                }
            },
            onCommitEdit: commitEdit,
            onCancelEdit: { editingTask = nil },
            onToggleComplete: {
                ProjectTasksStorage.updateTask(workspacePath: workspacePath, id: task.id, completed: !task.completed)
                reloadTasks()
            },
            onSendToAgent: { onSendToAgent(task.content, task.id, task.screenshotPaths) },
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
            } : nil
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tasks")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                Text((workspacePath as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
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
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))

                TextField("New task…", text: $newTaskDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                    .focused($isNewTaskFieldFocused)
                    .onSubmit { commitNewTask() }
                    .onKeyPress(.escape) {
                        cancelNewTask()
                        return .handled
                    }

                Button(action: cancelNewTask) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }

            TaskScreenshotDraftView(
                images: $newTaskScreenshots,
                showFileImporter: $showScreenshotFileImporter,
                thumbnailSize: CGSize(width: 72, height: 72)
            )
        }
        .padding(12)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .fileImporter(
            isPresented: $showScreenshotFileImporter,
            allowedContentTypes: [.image, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            let toAdd = urls.prefix(AppLimits.maxScreenshots - newTaskScreenshots.count)
            for url in toAdd {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                if let image = NSImage(contentsOf: url) {
                    newTaskScreenshots.append(image)
                }
            }
        }
    }

}

// MARK: - Task screenshot thumbnail (in todo row): tappable preview + delete

private struct TaskScreenshotThumbnailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    let screenshotPath: String
    var onTapPreview: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var imageURL: URL {
        ProjectTasksStorage.taskScreenshotFileURL(workspacePath: workspacePath, screenshotPath: screenshotPath)
    }

    /// Small "expand" icon overlay (matches ScreenshotCardView affordance). Dark scrim + white icon for contrast on any image.
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
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
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
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Task row

private struct TaskRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: ProjectTask
    let workspacePath: String
    /// When set, show a badge for the linked agent status (processing / done / open / stopped).
    var linkedTaskStatus: LinkedTaskStatus? = nil
    var isEditing: Bool = false
    @Binding var editDraft: String
    @Binding var editScreenshotImages: [NSImage]
    @Binding var showEditScreenshotFileImporter: Bool
    var isEditorFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onToggleComplete: () -> Void
    let onSendToAgent: () -> Void
    let onDelete: () -> Void
    var onPreviewScreenshot: ((String) -> Void)? = nil
    var onDeleteScreenshot: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggleComplete) {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.completed ? CursorTheme.brandBlue : CursorTheme.textTertiary(for: colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(isEditing)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing && !task.completed {
                    TextEditor(text: $editDraft)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        .scrollContentBackground(.hidden)
                        .lineSpacing(6)
                        .padding(.vertical, 4)
                        .frame(minHeight: 36, maxHeight: 160)
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
                    TaskScreenshotDraftView(
                        images: $editScreenshotImages,
                        showFileImporter: $showEditScreenshotFileImporter,
                        thumbnailSize: CGSize(width: 72, height: 72)
                    )
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(task.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(task.completed ? CursorTheme.textTertiary(for: colorScheme) : CursorTheme.textPrimary(for: colorScheme))
                            .strikethrough(task.completed)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { if !task.completed { onTap() } }
                        if let status = linkedTaskStatus {
                            taskStatusBadge(status)
                        }
                    }
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
                    Button("Edit task…", systemImage: "pencil") {
                        onTap()
                    }
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
        .padding(12)
        .background(CursorTheme.surfaceRaised(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
        )
        .contextMenu {
            Button(task.completed ? "Mark as not done" : "Mark as Done", systemImage: task.completed ? "circle" : "checkmark.circle") {
                onToggleComplete()
            }
            if !task.completed {
                Divider()
                Button("Send to new Agent", systemImage: "bubble.left.and.bubble.right") {
                    onSendToAgent()
                }
                Button("Edit task…", systemImage: "pencil") {
                    onTap()
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                onDelete()
            }
        }
    }

    @ViewBuilder
    private func taskStatusBadge(_ status: LinkedTaskStatus) -> some View {
        let (icon, color, label) = statusDisplay(status)
        HStack(spacing: 2) {
            if status == .processing {
                LightBlueSpinner(size: 10)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func statusDisplay(_ status: LinkedTaskStatus) -> (icon: String, color: Color, label: String) {
        switch status {
        case .open:
            return ("circle", CursorTheme.textTertiary(for: colorScheme), "open")
        case .processing:
            return ("arrow.trianglehead.2.clockwise.rotate.90", CursorTheme.brandBlue, "processing")
        case .done:
            return ("checkmark.circle.fill", CursorTheme.semanticSuccess, "done")
        case .stopped:
            return ("stop.fill", CursorTheme.semanticError, "stopped")
        }
    }
}

// MARK: - Screenshot draft (new task / edit): thumbnails + add controls

private struct TaskScreenshotDraftView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var images: [NSImage]
    @Binding var showFileImporter: Bool
    var thumbnailSize: CGSize

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, img in
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
                Button(action: { images.remove(at: index) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            if images.count < AppLimits.maxScreenshots {
                Menu {
                    Button("Paste from clipboard") {
                        if let pasted = SubmittableTextEditor.imageFromPasteboard(NSPasteboard.general) {
                            images.append(pasted)
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

