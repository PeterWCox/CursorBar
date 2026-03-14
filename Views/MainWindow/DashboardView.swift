import SwiftUI

// MARK: - Dashboard (Preview, Advanced) for a project

/// Dashboard tabs, matching the Tasks-style tab bar.
enum DashboardTab: String, CaseIterable {
    case preview = "Preview"
    case settings = "Advanced"
}

struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let workspacePath: String
    var onDismiss: () -> Void
    /// Remove this project from Cursor Metro without deleting files on disk.
    var onRemoveProject: () -> Void
    @Binding var selectedTab: DashboardTab

    @State private var debugURL: String = ""
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
        case .preview:
            EmptyView()
        case .settings:
            settingsContent
        }
    }

    // MARK: - Preview tab (terminal + Start Preview / Configure Setup)

    private static let defaultStartupScript = """
    #!/bin/bash
    # Add commands to build and start your app.
    # Example: npm run dev
    """

    private var previewContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: CursorTheme.spaceS) {
                let isConfigured = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
                    title: "Configure Setup",
                    icon: "gearshape",
                    action: {
                        let trimmed = startupScriptContents.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            ProjectSettingsStorage.setStartupScriptContents(workspacePath: workspacePath, Self.defaultStartupScript)
                            startupScriptContents = ProjectSettingsStorage.getStartupScriptContents(workspacePath: workspacePath) ?? Self.defaultStartupScript
                        }
                        selectedTab = .settings
                    },
                    help: "Set up .metro/startup.sh and open Advanced to set debug URL and startup script",
                    style: .accent
                )
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
                Text("This is the script that runs in your terminal so you can preview the app.")
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
