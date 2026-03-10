import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath

    @State private var globalCommands: [QuickActionCommand] = []
    @State private var projectCommands: [QuickActionCommand] = []
    @State private var editingCommand: QuickActionCommand?
    @State private var showAddSheet = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Projects root:")
                    TextField("~/dev", text: $projectsRootPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectProjectsRootFolder()
                    }
                }
            } header: {
                Text("Workspace Picker")
            } footer: {
                Text("Direct subfolders from this directory are shown in the project picker.")
            }

            Section {
                HStack {
                    Text("Workspace path:")
                    TextField("~/path/to/repo", text: $workspacePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectWorkspaceFolder()
                    }
                }
            } header: {
                Text("Repository")
            } footer: {
                Text("The directory (usually a git repo) where Cursor agent will work. Agent will use .cursor/rules and AGENTS.md from this path.")
            }

            Section {
                ForEach(globalCommands) { cmd in
                    quickActionRow(cmd, scope: .global)
                }
                ForEach(projectCommands) { cmd in
                    quickActionRow(cmd, scope: .project)
                }
                Button(action: { showAddSheet = true }) {
                    Label("Add quick action", systemImage: "plus.circle")
                }
            } header: {
                Text("Quick actions")
            } footer: {
                Text("Commands shown as buttons in the composer (e.g. Fix build, Commit & push). Global commands appear in all workspaces; project commands only when this workspace is selected.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 380)
        .onAppear { reloadCommands() }
        .onChange(of: workspacePath) { _, _ in reloadCommands() }
        .sheet(isPresented: $showAddSheet) {
            QuickActionEditSheet(workspacePath: workspacePath, existing: nil) { newCommand in
                addCommand(newCommand)
            }
        }
        .sheet(item: $editingCommand) { cmd in
            QuickActionEditSheet(workspacePath: workspacePath, existing: cmd) { updated in
                updateCommand(old: cmd, updated: updated)
                editingCommand = nil
            }
        }
    }

    @ViewBuilder
    private func quickActionRow(_ cmd: QuickActionCommand, scope: QuickActionCommand.Scope) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .foregroundStyle(CursorTheme.textSecondary)
                .frame(width: 22, alignment: .center)
            Text(cmd.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(scope == .global ? "Global" : "Project")
                .font(.caption)
                .foregroundStyle(CursorTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CursorTheme.surfaceMuted, in: Capsule())
            Button(action: { deleteCommand(cmd, scope: scope) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CursorTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { editingCommand = cmd }
    }

    private func reloadCommands() {
        globalCommands = QuickActionStorage.loadGlobalCommands()
        projectCommands = QuickActionStorage.loadProjectCommands(workspacePath: workspacePath)
    }

    private func addCommand(_ cmd: QuickActionCommand) {
        if cmd.scope == .project {
            projectCommands.append(cmd)
            QuickActionStorage.saveProjectCommands(workspacePath: workspacePath, projectCommands)
        } else {
            globalCommands.append(cmd)
            QuickActionStorage.saveGlobalCommands(globalCommands)
        }
    }

    private func updateCommand(old: QuickActionCommand, updated: QuickActionCommand) {
        let wasGlobal = old.scope == .global
        if wasGlobal {
            globalCommands.removeAll { $0.id == old.id }
            QuickActionStorage.saveGlobalCommands(globalCommands)
        } else {
            projectCommands.removeAll { $0.id == old.id }
            QuickActionStorage.saveProjectCommands(workspacePath: workspacePath, projectCommands)
        }
        if updated.scope == .global {
            globalCommands.append(updated)
            QuickActionStorage.saveGlobalCommands(globalCommands)
        } else {
            projectCommands.append(updated)
            QuickActionStorage.saveProjectCommands(workspacePath: workspacePath, projectCommands)
        }
        reloadCommands()
    }

    private func deleteCommand(_ cmd: QuickActionCommand, scope: QuickActionCommand.Scope) {
        if scope == .global {
            globalCommands.removeAll { $0.id == cmd.id }
            QuickActionStorage.saveGlobalCommands(globalCommands)
        } else {
            projectCommands.removeAll { $0.id == cmd.id }
            QuickActionStorage.saveProjectCommands(workspacePath: workspacePath, projectCommands)
        }
    }

    private func selectWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if !workspacePath.isEmpty && FileManager.default.fileExists(atPath: workspacePath) {
            panel.directoryURL = URL(fileURLWithPath: workspacePath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
        }
    }

    private func selectProjectsRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let currentRootPath = AppPreferences.resolvedProjectsRootPath(projectsRootPath)
        if FileManager.default.fileExists(atPath: currentRootPath) {
            panel.directoryURL = URL(fileURLWithPath: currentRootPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            projectsRootPath = url.path
        }
    }
}
