import SwiftUI
#if DEBUG
import Inject
#endif

struct SettingsView: View {
    #if DEBUG
    @ObserveInjection var inject
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var projectSettingsStore: ProjectSettingsStore
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @AppStorage(AppPreferences.disabledModelIdsKey) private var disabledModelIdsRaw: String = AppPreferences.defaultDisabledModelIdsRaw

    @State private var globalCommands: [QuickActionCommand] = []
    @State private var projectCommands: [QuickActionCommand] = []
    @State private var editingCommand: QuickActionCommand?
    @State private var debugURL: String = ""
    @State private var startupScriptContents: String = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("View in Browser URL:")
                    TextField("", text: $debugURL)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup scripts (one per line)")
                    TextEditor(text: $startupScriptContents)
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
            } header: {
                Text("Project settings")
            } footer: {
                Text("View in Browser URL opens in Chrome when you use \"Open in Browser\". Startup scripts are in .metro/project.json (scripts array). Preview runs each script in its own in-app tab (e.g. backend + frontend).")
            }

            Section {
                Picker("Preferred terminal:", selection: $preferredTerminalAppRawValue) {
                    ForEach(PreferredTerminalApp.allCases) { terminal in
                        Text(terminal.displayName).tag(terminal.rawValue)
                    }
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Used by the Debug button to launch `debug.sh` from the selected workspace.")
            }

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
                HStack(spacing: 8) {
                    Button("Select all") {
                        disabledModelIdsRaw = AppPreferences.defaultDisabledModelIdsRaw
                    }
                    .buttonStyle(.bordered)
                    Button("Deselect all") {
                        let allIds = Set(appState.availableModels.map(\.id))
                        disabledModelIdsRaw = AppPreferences.rawFrom(disabledIds: allIds)
                    }
                    .buttonStyle(.bordered)
                }
                ForEach(appState.availableModels, id: \.id) { model in
                    Toggle(model.label, isOn: Binding(
                        get: { !AppPreferences.disabledModelIds(from: disabledModelIdsRaw).contains(model.id) },
                        set: { enabled in
                            var set = AppPreferences.disabledModelIds(from: disabledModelIdsRaw)
                            if enabled { set.remove(model.id) } else { set.insert(model.id) }
                            disabledModelIdsRaw = AppPreferences.rawFrom(disabledIds: set)
                        }
                    ))
                    .controlSize(.small)
                }
            } header: {
                Text("Model Picker")
            } footer: {
                Text("Choose which models appear in the model picker. By default all are shown.")
            }

            Section {
                ForEach(globalCommands) { cmd in
                    quickActionRow(cmd, scope: .global)
                }
                ForEach(projectCommands) { cmd in
                    quickActionRow(cmd, scope: .project)
                }
            } header: {
                Text("Quick actions")
            } footer: {
                Text("Commands shown as buttons in the composer (e.g. Fix build, Commit & push). Global commands appear in all workspaces; project commands only when this workspace is selected.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .onAppear {
            appState.loadModelsFromCLI()
            reloadCommands()
            let snapshot = projectSettingsStore.snapshot(for: workspacePath)
            debugURL = snapshot.debugURL
            startupScriptContents = snapshot.startupScripts.joined(separator: "\n")
        }
        .onChange(of: workspacePath) { _, _ in
            reloadCommands()
            let snapshot = projectSettingsStore.snapshot(for: workspacePath)
            debugURL = snapshot.debugURL
            startupScriptContents = snapshot.startupScripts.joined(separator: "\n")
        }
        .onDisappear {
            let trimmedUrl = debugURL.trimmingCharacters(in: .whitespacesAndNewlines)
            projectSettingsStore.setDebugURL(workspacePath: workspacePath, trimmedUrl.isEmpty ? nil : trimmedUrl)
            let scripts = startupScriptContents
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            projectSettingsStore.setStartupScripts(workspacePath: workspacePath, scripts)
        }
        .sheet(item: $editingCommand) { cmd in
            QuickActionEditSheet(workspacePath: workspacePath, existing: cmd) { updated in
                updateCommand(old: cmd, updated: updated)
                editingCommand = nil
            }
        }
        #if DEBUG
        .enableInjection()
        #endif
    }

    @ViewBuilder
    private func quickActionRow(_ cmd: QuickActionCommand, scope: QuickActionCommand.Scope) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.icon)
                .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                .frame(width: 22, alignment: .center)
            Text(cmd.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(scope == .global ? "Global" : "Project")
                .font(.caption)
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(CursorTheme.surfaceMuted(for: colorScheme), in: Capsule())
            Button(action: { deleteCommand(cmd, scope: scope) }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
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
