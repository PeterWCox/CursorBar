import SwiftUI

// MARK: - Dashboard (Settings, Git) for a project

/// Dashboard tabs, matching the Tasks-style tab bar.
enum DashboardTab: String, CaseIterable {
    case settings = "Settings"
    case git = "Git"
    case preview = "Preview"
}

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    /// Current branch and list for Git tab (from parent).
    var currentBranch: String = ""
    var gitBranches: [String] = []
    var onDismiss: () -> Void
    /// Create a linked task and agent tab that configures project settings for this workspace.
    var onConfigureProject: (String, String) -> Void
    /// Remove this project from Cursor Metro without deleting files on disk.
    var onRemoveProject: () -> Void
    /// Called after successfully initialising a git repo so the parent can refresh branch state.
    var onGitInitialized: ((String) -> Void)?
    @Binding var selectedTab: DashboardTab

    @State private var debugURL: String = ""
    @State private var gitInitError: String?
    @State private var isInitializingGit = false
    @State private var debugInstructions: String = ""
    @State private var startupScriptContents: String = ""
    /// When non-nil, the Preview terminal runs this command (e.g. startup script). When user taps "Run startup script", we set this and bump previewTerminalKey to recreate the terminal.
    @State private var previewTerminalCommand: String? = nil
    @State private var previewTerminalKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            dashboardTabBar
            Divider()
                .background(CursorTheme.border(for: colorScheme))
            if selectedTab == .preview {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    tabContent()
                        .padding(CursorTheme.paddingPanel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            debugURL = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) ?? ""
            debugInstructions = ProjectSettingsStorage.getDebugInstructions(workspacePath: workspacePath) ?? ""
            startupScriptContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: CursorTheme.spaceM) {
            Button(action: onDismiss) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: CursorTheme.fontIconList, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("Dashboard")
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

    private var dashboardTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
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

    @ViewBuilder
    private func tabContent() -> some View {
        switch selectedTab {
        case .settings:
            settingsContent
        case .git:
            gitContent
        case .preview:
            EmptyView()
        }
    }

    // MARK: - Preview tab (terminal + Run startup script)

    private var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: CursorTheme.spaceS) {
                let hasScript = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                Button {
                    // Run the script file so $0 is .metro/startup.sh (not "bash"); script can safely use cd "$(dirname "$0")/.."
                    previewTerminalCommand = hasScript ? "bash .metro/startup.sh" : nil
                    previewTerminalKey = UUID()
                } label: {
                    Label("Run startup script", systemImage: "play.fill")
                        .font(.system(size: CursorTheme.fontBody, weight: .semibold))
                        .foregroundStyle(hasScript ? CursorTheme.brandPurple : CursorTheme.textTertiary(for: colorScheme))
                }
                .buttonStyle(.plain)
                .disabled(!hasScript)
                .help(hasScript ? "Run .metro/startup.sh in the terminal below" : "Add a startup script in Settings first")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CursorTheme.paddingPanel)
            .padding(.vertical, CursorTheme.spaceS)
            .background(CursorTheme.chrome(for: colorScheme))
            EmbeddedTerminalView(
                workspacePath: workspacePath,
                isSelected: true,
                initialCommand: previewTerminalCommand
            )
            .id(previewTerminalKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Settings tab

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceL) {
            // Debug URL
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text("Debug URL")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                TextField("http://localhost:3000", text: $debugURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(CursorTheme.spaceS)
                    .background(CursorTheme.surfaceMuted(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
                    .onChange(of: debugURL) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, trimmed.isEmpty ? nil : trimmed)
                    }
            }

            // Startup script (.metro/startup.sh) — single combined section: filename + contents
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text("Startup script (startup.sh)")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                Text("Shell script that builds/starts the app. Stored in `.metro/startup.sh`. If multiple processes are needed, run them via npx concurrently or similar.")
                    .font(.system(size: CursorTheme.fontCaption, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                TextEditor(text: $startupScriptContents)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(CursorTheme.spaceS)
                    .frame(minHeight: 80, maxHeight: 160)
                    .background(CursorTheme.surfaceMuted(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
                    .onChange(of: startupScriptContents) { _, newValue in
                        ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, newValue.isEmpty ? nil : newValue)
                    }
            }

            // Debug instructions (used when creating agent for terminal debugging)
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text("Debug instructions")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                Text("Instructions for the agent when debugging (e.g. what to do when the terminal is opened).")
                    .font(.system(size: CursorTheme.fontCaption, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                TextEditor(text: $debugInstructions)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(CursorTheme.spaceS)
                    .frame(minHeight: 80, maxHeight: 140)
                    .background(CursorTheme.surfaceMuted(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
                    )
                    .onChange(of: debugInstructions) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        ProjectSettingsStorage.setDebugInstructions(workspacePath: workspacePath, trimmed.isEmpty ? nil : trimmed)
                    }
            }

            VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                Text("Project configuration")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                Text("Create a linked task and agent tab to configure `.metro`: set debug URL (for web projects only), create or edit `.metro/startup.sh` (using e.g. concurrently if multiple processes are needed), and optional debug instructions.")
                    .font(.system(size: CursorTheme.fontBodySmall, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    createConfigurationTask()
                } label: {
                    Label("Configure", systemImage: "wand.and.stars")
                        .font(.system(size: CursorTheme.fontBody, weight: .semibold))
                        .foregroundStyle(CursorTheme.brandPurple)
                }
                .buttonStyle(.plain)
                .help("Create a linked task and agent tab to configure this project")
            }
            .padding(CursorTheme.paddingCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CursorTheme.surfaceRaised(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                Text("Remove from Cursor Metro")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                Text("Remove this project from the sidebar and close its tabs in Cursor Metro. This does not delete the project folder or any files on disk.")
                    .font(.system(size: CursorTheme.fontBodySmall, weight: .regular))
                    .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onRemoveProject()
                } label: {
                    Label("Remove project", systemImage: "xmark.circle")
                        .font(.system(size: CursorTheme.fontBody, weight: .semibold))
                        .foregroundStyle(CursorTheme.semanticError)
                }
                .buttonStyle(.plain)
                .help("Remove this project from Cursor Metro without deleting any files")
            }
            .padding(CursorTheme.paddingCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CursorTheme.surfaceRaised(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func createConfigurationTask() {
        persistSettings()
        onConfigureProject("Configure Cursor Metro project settings", configurationPrompt())
    }

    private func persistSettings() {
        let trimmedURL = debugURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInstructions = debugInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, trimmedURL.isEmpty ? nil : trimmedURL)
        ProjectSettingsStorage.setDebugInstructions(workspacePath: workspacePath, trimmedInstructions.isEmpty ? nil : trimmedInstructions)
        ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, startupScriptContents.isEmpty ? nil : startupScriptContents)
    }

    private func configurationPrompt() -> String {
        let url = debugURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = debugInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let scriptContents = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines)

        var prompt = """
        Configure this project for Cursor Metro.

        1. Debug URL: In `.metro/project.json`, set `debugUrl` only if this is a web development project that exposes a local browser URL for debugging (e.g. http://localhost:3000). If it is not a web project (e.g. CLI, mobile app, backend-only), leave `debugUrl` blank or omit it.

        2. Startup script: Create or edit the file `.metro/startup.sh` with a shell script that builds and/or starts the app from the command line. The script should kill any ports the app uses first (e.g. with lsof -i :PORT and kill, or a small helper) so reruns don't fail with "port in use". Cursor Metro runs only one script in one terminal, so:
           - If the project needs more than one process (e.g. frontend dev server + backend API, or multiple services), run them all from that one script using `npx concurrently` (or similar: npm-run-all, a small wrapper script that backgrounds processes, etc.) so everything runs in a single terminal session.
           - Otherwise a single-command script is fine.

        3. Keep `.metro/project.json` valid JSON and briefly explain what you changed.
        """

        if !url.isEmpty {
            prompt += "\n\nExisting debug URL to preserve or refine if still correct: \(url)"
        }
        if !instructions.isEmpty {
            prompt += "\nExisting debug instructions: \(instructions)"
        }
        if !scriptContents.isEmpty {
            prompt += "\n\nExisting `.metro/startup.sh` contents to reuse or replace if needed:\n\(scriptContents)"
        }

        return prompt
    }

    // MARK: - Git tab

    private var gitContent: some View {
        Group {
            if isGitRepository(workspacePath: workspacePath) {
                gitRepoContent
            } else {
                gitNoRepoContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gitRepoContent: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
            Text("Branch")
                .font(.system(size: CursorTheme.fontSubtitle, weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            if currentBranch.isEmpty {
                Text("No branch (no commits yet)")
                    .font(.system(size: 13))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
            } else {
                Text(currentBranch)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            }
            if !gitBranches.isEmpty {
                Text("Branches")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .padding(.top, CursorTheme.spaceS)
                ForEach(gitBranches, id: \.self) { branch in
                    Text(branch)
                        .font(.system(size: 13))
                        .foregroundStyle(branch == currentBranch ? CursorTheme.textPrimary(for: colorScheme) : CursorTheme.textSecondary(for: colorScheme))
                }
            }
        }
    }

    private var gitNoRepoContent: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceL) {
            VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
                HStack(spacing: CursorTheme.spaceS) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: CursorTheme.fontTitle, weight: .medium))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .symbolRenderingMode(.hierarchical)
                    Text("No Git repository")
                        .font(.system(size: CursorTheme.fontSubtitle, weight: .semibold))
                        .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                }
                Text("This folder is not a Git repository. Initialize one to track changes and use branch features in Cursor Metro.")
                    .font(.system(size: CursorTheme.fontBodySmall, weight: .regular))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CursorTheme.paddingCard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CursorTheme.surfaceRaised(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                    .stroke(CursorTheme.border(for: colorScheme), lineWidth: 1)
            )

            if let err = gitInitError {
                HStack(spacing: CursorTheme.spaceS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: CursorTheme.fontSecondary))
                        .foregroundStyle(CursorTheme.semanticError)
                    Text(err)
                        .font(.system(size: CursorTheme.fontBodySmall))
                        .foregroundStyle(CursorTheme.semanticError)
                }
                .padding(CursorTheme.spaceS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CursorTheme.semanticErrorTint.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous))
            }

            Button {
                initializeGitRepository()
            } label: {
                Label(isInitializingGit ? "Initializing…" : "Initialize Git repository", systemImage: "plus.circle.fill")
                    .font(.system(size: CursorTheme.fontBody, weight: .semibold))
                    .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
            }
            .buttonStyle(.plain)
            .disabled(isInitializingGit)
            .help("Run git init in this folder")
        }
    }

    private func initializeGitRepository() {
        gitInitError = nil
        isInitializingGit = true
        let err = gitInit(workspacePath: workspacePath)
        isInitializingGit = false
        if let err = err {
            gitInitError = err
            return
        }
        onGitInitialized?(workspacePath)
    }
}
