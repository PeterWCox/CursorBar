import SwiftUI
import AppKit

struct GeneralSettingsPaneContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.askCompletionNotificationsEnabledKey)
    private var askCompletionNotificationsEnabled: Bool = AppPreferences.defaultAskCompletionNotificationsEnabled
    @AppStorage(AppPreferences.projectsRootPathKey) private var projectsRootPath: String = AppPreferences.defaultProjectsRootPath
    @AppStorage("workspacePath") private var workspacePath: String = FileManager.default.homeDirectoryForCurrentUser.path
    @AppStorage(AppPreferences.preferredTerminalAppKey) private var preferredTerminalAppRawValue: String = PreferredTerminalApp.automatic.rawValue
    @AppStorage(AppPreferences.selectedAgentProviderIDKey) private var selectedAgentProviderIDRawValue: String = AgentProviderID.claudeCode.rawValue

    private var selectedAgentProviderID: AgentProviderID {
        AgentProviderID(rawValue: selectedAgentProviderIDRawValue) ?? .claudeCode
    }

    private var metroAppMarketingName: String {
        selectedAgentProviderID.metroAppMarketingName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceXL) {
            settingsSection(title: "Workspace") {
                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                        Text("Projects folder")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        Text("Direct subfolders are discovered and listed in the sidebar. Import still adds any folder you choose.")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: CursorTheme.spaceS) {
                            TextField("~/dev", text: $projectsRootPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") { selectProjectsRootFolder() }
                        }
                    }

                    Divider()
                        .background(CursorTheme.border(for: colorScheme).opacity(0.6))

                    VStack(alignment: .leading, spacing: CursorTheme.spaceXS) {
                        Text("Default repository")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .semibold))
                            .foregroundStyle(CursorTheme.textPrimary(for: colorScheme))
                        Text("Used when you open System Settings and as the starting path for agent work unless you pick another project in the sidebar.")
                            .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                            .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: CursorTheme.spaceS) {
                            TextField("~/path/to/repo", text: $workspacePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse…") { selectWorkspaceFolder() }
                        }
                    }
                }
            }

            settingsSection(title: "Agent") {
                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    Picker("Backend", selection: $selectedAgentProviderIDRawValue) {
                        ForEach(AgentProviderID.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }

                    Text("Choose between Cursor Agent or Claude Code CLI. New tasks and tabs will use the selected backend. Existing tasks are locked to their creation-time backend.")
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSection(title: "Terminal") {
                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    Picker("Open Debug scripts in", selection: $preferredTerminalAppRawValue) {
                        ForEach(PreferredTerminalApp.allCases) { terminal in
                            Text(terminal.displayName).tag(terminal.rawValue)
                        }
                    }

                    Text("Used when Metro launches a terminal for Debug or external script flows.")
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSection(title: "Ask completions") {
                VStack(alignment: .leading, spacing: CursorTheme.spaceM) {
                    Toggle("Notify when an ask finishes", isOn: $askCompletionNotificationsEnabled)
                        .toggleStyle(.switch)

                    Text("Shows a macOS notification when \(metroAppMarketingName) finishes or fails an ask. The notification title uses the task or tab title.")
                        .font(.system(size: CursorTheme.fontSecondary, weight: .regular))
                        .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CursorTheme.spaceS) {
            Text(title)
                .font(.system(size: CursorTheme.fontSmall, weight: .semibold))
                .foregroundStyle(CursorTheme.textTertiary(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)

            content()
                .padding(CursorTheme.paddingCard)
                .background(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .fill(CursorTheme.surfaceMuted(for: colorScheme).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CursorTheme.radiusCard, style: .continuous)
                        .stroke(CursorTheme.border(for: colorScheme).opacity(0.6), lineWidth: 1)
                )
        }
    }

    private func selectWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Default repository"
        panel.message = "Choose the folder Claude Code should use by default."

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
        panel.title = "Projects folder"
        panel.message = "Metro scans immediate subfolders of this directory for projects."

        let currentRootPath = AppPreferences.resolvedProjectsRootPath(projectsRootPath)
        if FileManager.default.fileExists(atPath: currentRootPath) {
            panel.directoryURL = URL(fileURLWithPath: currentRootPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            projectsRootPath = url.path
        }
    }
}

#Preview {
    GeneralSettingsPaneContent()
        .padding(24)
        .background(CursorTheme.surface(for: .dark))
}
