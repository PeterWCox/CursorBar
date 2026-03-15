import SwiftUI
#if DEBUG
import Inject
#endif

// MARK: - Dashboard (Preview, Advanced) for a project

/// Dashboard tabs, matching the Tasks-style tab bar.
enum DashboardTab: String, CaseIterable {
    case preview = "Preview"
    case settings = "Advanced"
}

struct DashboardView: View {
    #if DEBUG
    @ObserveInjection var inject
    #endif
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    var onDismiss: () -> Void
    /// Remove this project from Cursor Metro without deleting files on disk.
    var onRemoveProject: () -> Void
    @Binding var selectedTab: DashboardTab
    /// When set, Regenerate Setup (and Configure Setup when not configured) launches an agent with a setup prompt instead of switching to Advanced. Call with workspace path.
    var onLaunchSetupAgent: ((String) -> Void)? = nil
    /// When false, the view does not show its own header (e.g. when the panel title row already shows "Preview" + project).
    var showHeader: Bool = true

    @State private var debugURL: String = ""
    @State private var startupScriptContents: String = ""
    /// When non-nil, the Preview terminal runs this command (e.g. startup script). When user taps "Run startup script", we set this and bump previewTerminalKey to recreate the terminal.
    @State private var previewTerminalCommand: String? = nil
    @State private var previewTerminalKey = UUID()

    var body: some View {
        VStack(spacing: 0) {
            if showHeader { header }
            dashboardTabBar
            Divider()
                .background(CursorTheme.border(for: colorScheme))
            // Preview tab and internal terminal commented out; preview buttons moved to Tasks → In Progress. Uncomment to restore.
            // if selectedTab == .preview {
            //     previewContent
            //         .frame(maxWidth: .infinity, maxHeight: .infinity)
            // } else {
            ScrollView(.vertical, showsIndicators: true) {
                tabContent()
                    .padding(CursorTheme.paddingPanel)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            debugURL = ProjectSettingsStorage.getDebugURL(workspacePath: workspacePath) ?? ""
            startupScriptContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? ""
        }
        #if DEBUG
        .enableInjection()
        #endif
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
                Text("Preview")
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
            // Only show Advanced; Preview tab commented out (buttons moved to Tasks → In Progress)
            ForEach([DashboardTab.settings], id: \.self) { tab in
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
        // case .preview:
        //     EmptyView()
        case .settings:
            settingsContent
        case .preview:
            EmptyView() // keep for enum exhaustiveness; tab bar hides .preview
        }
    }

    // MARK: - Preview tab (terminal + Start Preview / Configure Setup) — commented out for later; use Tasks → In Progress + external terminal

    private static let defaultStartupScript = """
    #!/bin/bash
    # This script runs with cwd = project root (the folder that contains .metro). Do not cd into .metro.
    # Add commands to build and start your app, e.g. npm run dev or: cd budget && npm run dev
    """

    /// Prompt sent to the agent when launching setup/regenerate. Agent creates .metro/startup.sh and .metro/project.json (debugUrl) from scratch.
    static let setupAgentPrompt = """
    Set up Cursor Metro for this project from scratch.

    1) Create or overwrite .metro/startup.sh with a script that builds and runs the app. Use #!/bin/bash and make the script executable.

    Important: The script is always run with the shell's current working directory set to the **project root** (the directory that contains .metro), NOT inside .metro. Write the script as if it runs in the project root: use commands like `npm run dev` if package.json is in the project root, or `cd budget && npm run dev` (or whatever the app subfolder is) if the app lives in a subfolder. Do not cd into .metro or assume the script runs from .metro.

    2) If this is a web app, create or update .metro/project.json with a "debugUrl" field set to the URL where the app is served (e.g. http://localhost:3000).

    Detect the project type from the repo (package.json, etc.) and configure accordingly.
    """

    #if false // Preview tab + internal terminal: restore by setting to true and uncommenting body branch + tab bar
    private var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: CursorTheme.spaceS) {
                let isConfigured = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let terminalRunning = previewTerminalCommand != nil
                let hasPreviewURL = (debugURL.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty == false

                if terminalRunning {
                    ActionButton(
                        title: "Stop",
                        icon: "stop.fill",
                        action: {
                            previewTerminalCommand = nil
                            previewTerminalKey = UUID()
                        },
                        help: "Stop the process and reset the terminal",
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
                                previewTerminalCommand = "bash .metro/startup.sh"
                                previewTerminalKey = UUID()
                            },
                            help: "Run .metro/startup.sh in the terminal below",
                            style: .play
                        )
                    }
                    ActionButton(
                        title: isConfigured ? "Regenerate Setup" : "Configure Setup",
                        icon: "gearshape",
                        action: {
                            if let launch = onLaunchSetupAgent {
                                launch(workspacePath)
                                return
                            }
                            if isConfigured {
                                ProjectSettingsStorage.setDebugURL(workspacePath: workspacePath, nil)
                                debugURL = ""
                                ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, Self.defaultStartupScript)
                                startupScriptContents = Self.defaultStartupScript
                            } else {
                                let trimmed = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty {
                                    ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, Self.defaultStartupScript)
                                    startupScriptContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? Self.defaultStartupScript
                                }
                            }
                            selectedTab = .settings
                        },
                        help: onLaunchSetupAgent != nil
                            ? (isConfigured ? "Launch an agent to regenerate .metro/startup.sh and debug URL from scratch" : "Launch an agent to set up .metro/startup.sh and debug URL for this project")
                            : (isConfigured ? "Reset startup script to default and open Advanced to reconfigure" : "Set up .metro/startup.sh and open Advanced to set debug URL and startup script"),
                        style: .accent
                    )
                }
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
    #endif

    // MARK: - Settings tab

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceL) {
            // Preview URL (debug URL for web projects)
            VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                Text("Preview URL")
                    .font(.system(size: CursorTheme.fontSecondary, weight: .medium))
                    .foregroundStyle(CursorTheme.textSecondary(for: colorScheme))
                TextField("", text: $debugURL)
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
                Text("This script runs with the terminal’s working directory set to the project root (the folder that contains .metro). Use paths or cd relative to the project root.")
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
}
