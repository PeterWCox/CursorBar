# Cursor Metro — OOP Structure

High-level object-oriented structure of the Cursor Metro macOS app: entry point, state, models, views, services, and helpers. Use this to see how types are grouped and how the UI is composed.

---

## 1. App lifecycle & shell

- **CursorPlusApp** (`App`) — SwiftUI `@main` entry. Uses `NSApplicationDelegateAdaptor(AppDelegate.self)` so the menu-bar app is driven by AppKit.
- **AppDelegate** (`NSObject`, `NSApplicationDelegate`) — Creates the status bar item, owns **FloatingPanel**, wires **AppState** (including collapse/expand), and positions the panel (near status item or from saved frame). Handles “Open in Browser” (Cmd+O), quit (saves tab state + panel frame), and reopen from Dock.
- **FloatingPanel** (`NSPanel`) — Borderless, resizable floating window; min/max size and restore from **PanelFrameStorage**. Hosts the root SwiftUI view.
- **PanelFrameStorage** — Static helpers to save/load panel frame (UserDefaults) for restore on next launch.
- **StatusItemView** — Custom `NSView` for the menu bar icon; left-click toggles panel, right-click shows context menu (Settings, Center Popup, Quit).
- **AppState** (`ObservableObject`) — Global app state: workspace path, projects root, settings sheet, “Open in Browser” request, collapsed/expanded panel, open project count, **TabManager**, and available models (from CLI). Exposes `changeWorkspace(completion:)` for folder picker and `workspaceDisplayName(for:)`.

---

## 2. State & tab management

- **TabManager** (`ObservableObject`) — Single source of truth for projects, agent tabs, terminal tabs, and selection (`selectedTabID`, `selectedTerminalID`, `selectedTasksViewPath`, `selectedProjectPath`). Adds/removes tabs and projects, shows/hides Tasks view, keeps “recently closed tabs” for Cmd+Shift+T. Persists via **TabManagerPersistence**.
- **AgentTab** (`ObservableObject`, `Identifiable`) — One agent conversation: title, workspace path, current branch, prompt, turns, follow-up queue, linked task ID, streaming state. Publishes so the sidebar chip and content area can react to `isRunning` and turn updates without re-rendering the whole window.
- **TerminalTab** (`ObservableObject`, `Identifiable`) — One embedded terminal: title, workspace path.
- **TabManagerPersistence** — Load/save **SavedTabState** (tabs, selection, projects) to Application Support JSON.
- **SavedTabState**, **SavedAgentTab**, **SavedProject** — Codable DTOs for tab/project persistence. **ProjectState** is the in-memory project (path only, `Identifiable` by path).

---

## 3. Domain models

- **ConversationTurn**, **ConversationSegment**, **ConversationSegmentKind** — One user message and the assistant’s response segments (thinking, assistant text, tool calls). **ToolCallSegmentData** holds call id, title, detail, status. **StreamPhase** and **ConversationTurnDisplayState** describe streaming and display state (processing / completed / stopped).
- **QueuedFollowUp** — Pending follow-up message for an agent tab.
- **LinkedTaskStatus** — Task status for sidebar: open, processing, done, stopped.
- **ProjectTask** — A single task (id, content, completed, completedAt, screenshotPaths). Used by Tasks list and **ProjectTasksStorage**.
- **AgentStreamChunk**, **AgentToolCallUpdate**, **AgentToolCallStatus**, **AgentRunnerError** — Used by **AgentRunner** for streaming and tool-call updates.

---

## 4. UI hierarchy (SwiftUI views)

Root content is **PopoutView**, which can show:

- **Sidebar** — Groups by project; each group has **ObservedTabChip** (agent tabs), **TerminalTabChip** (terminal tabs), and a “Tasks” entry. **TabChip** shows title, optional **linkedTaskStatus** badge, and uses **LightBlueSpinner** when running. **WorkspacePickerView** and **GitBranchPickerView** live in the main flow; **ProjectIconView** shows folder icon from path.
- **Main content** — Either:
  - **TasksListView** for the selected project (task list, add/edit/complete, send to agent), which uses **TaskRowView**, **TaskScreenshotThumbnailView**, **TaskScreenshotDraftView**, etc., or
  - Agent content: top bar (**BrandMark**, **ModelPickerView**, **QuickActionButtonsView**), composer (**SubmittableTextEditor**, **ComposerActionButtonsView**, **PinnedQuestionsView**, **CreateDebugScriptSheet**), and output (**OutputScrollView**, **ConversationViews**: **ConversationTurnView**, **ConversationSegmentView**, **ProcessingPlaceholderView**, **StoppedPlaceholderView**; **ScreenshotCardView**, **ScreenshotPreviewModal**), or
  - **EmbeddedTerminalView** for the selected terminal tab.

Other UI:

- **Settings** — **SettingsView** (with **SettingsModalView**, **KeyboardShortcutsView**) presented from AppState.
- **Quick actions** — **QuickActionCommand**, **QuickActionStorage**, **QuickActionEditSheet**.
- **Theme / shared** — **CursorTheme**, **DialogButtonStyles**; **ActionButton**, **AppDialogSheet**, **MetroSpeechBubble**.

---

## 5. Services

- **AgentRunner** — Runs the Cursor CLI agent (stream-json). Parses stream events into **AgentStreamChunk** (thinking, assistant text, tool calls), handles auth and process errors (**AgentRunnerError**), and provides `listModels()`. Used by **AgentTab** to run and stream turns.

---

## 6. Helpers & storage

- **ProjectTasksStorage** — Reads/writes per-project tasks (and task screenshots) under `.metro/` (e.g. `tasks.json`, `screenshots/`). Uses **ProjectTask** and a private **ProjectTasksFile** Codable.
- **ProjectSettingsStorage** — Per-project settings (e.g. under `.metro`).
- **AppPreferences** — UserDefaults-backed app preferences (e.g. projects root, disabled models, terminal app).
- **WorkspaceHelpers** — Path/workspace utilities; **PreferredTerminalApp** enum for terminal app selection.
- **TooltipModifier** — SwiftUI modifier for tooltips.

---

## 7. Theme & app constants

- **CursorTheme** — Central design tokens: colors (chrome, panel, surface, text, brand, premium), gradients, `colorForWorkspace(path:)`.
- **ModelOption**, **AvailableModels** — Model id/label/premium; fallback list and visibility filtering.
- **QuickActionPrompts** — Predefined prompts (e.g. fix build, commit and push).
- **AppLimits** — Max screenshots, context token limit, usage quota.
- **MenuBarIcon**, **CursorAppIcon**, **BrandStatusIcon**, **BrandAppIconView** — Menu bar and branding assets.

---

## YAML tree (types by location)

```yaml
App:
  CursorPlusApp: "@main SwiftUI App"
  AppDelegate: "NSApplicationDelegate; status item, panel, AppState"
  FloatingPanel: "NSPanel; hosts PopoutView"
  PanelFrameStorage: "save/load panel frame"
  StatusItemView: "NSView for menu bar icon"
  AppState: "ObservableObject; global state, TabManager, models"

Models:
  AgentTabState:
    SavedProject: "Codable"
    SavedAgentTab: "Codable"
    SavedTabState: "Codable"
    LinkedTaskStatus: "enum: open | processing | done | stopped"
    TabManagerPersistence: "load/save SavedTabState"
    QueuedFollowUp: "Identifiable, Codable"
    TerminalTab: "ObservableObject, Identifiable"
    AgentTab: "ObservableObject, Identifiable"
    ProjectState: "Identifiable, Codable"
    TabManager: "ObservableObject"
  ConversationModels:
    ConversationSegmentKind: "enum"
    ToolCallSegmentStatus: "enum"
    ToolCallSegmentData: "struct"
    ConversationSegment: "Identifiable, Codable"
    ConversationTurn: "Identifiable, Codable"
    StreamPhase: "enum"
    ConversationTurnDisplayState: "enum"

Views:
  MainWindow:
    PopoutView: "root; sidebar + main content"
    TasksListView: "project tasks; TaskRowView, thumbnails"
    EmbeddedTerminalView: "NSViewRepresentable"
    Sidebar:
      TabChip: "chip for agent tab; LightBlueSpinner, linkedTaskStatus"
      ObservedTabChip: "wraps TabChip, observes AgentTab"
      TerminalTabChip: "chip for terminal tab"
      WorkspacePickerView: "workspace/folder picker"
      GitBranchPickerView: "branch picker; NewBranchSheet"
      ProjectIconView: "folder icon from path"
    TopBar:
      BrandMark: "logo/title"
      ModelPickerView: "model selector"
      QuickActionButtonsView: "quick actions"
    Composer:
      SubmittableTextEditor: "NSViewRepresentable text input"
      ComposerActionButtonsView: "send, etc."
      ContextUsageView: "context usage"
      UsageView: "usage display"
      PinnedQuestionsView: "PinnedQuestionsStackView, PinnedQuestionChip"
      CreateDebugScriptSheet: "debug script sheet"
    Output:
      OutputScrollView: "scroll container"
      ConversationViews:
        ConversationTurnView: "one turn"
        ConversationSegmentView: "segment (thinking/assistant/tool)"
        ProcessingPlaceholderView: "streaming placeholder"
        StoppedPlaceholderView: "stopped placeholder"
      ScreenshotCardView: "screenshot in conversation"
      ScreenshotPreviewModal: "full-screen screenshot preview"
    QuickActions:
      QuickActionCommand: "Identifiable, Codable"
      QuickActionIcons: "enum"
      QuickActionStorage: "persistence"
      QuickActionEditSheet: "edit quick action"
  Settings:
    SettingsView: "root settings"
    SettingsModalView: "modal wrapper"
    KeyboardShortcutsView: "shortcuts list"
  Components:
    ActionButton: "reusable button"
    AppDialogSheet: "generic dialog sheet"
    MetroSpeechBubble: "bubble UI"
  Theme:
    CursorTheme: "colors, gradients"
    DialogButtonStyles: "DialogSecondaryButtonStyle, DialogPrimaryButtonStyle"

Services:
  AgentRunner: "Cursor CLI; stream parsing, listModels"
  AgentStreamChunk: "enum"
  AgentToolCallStatus: "enum"
  AgentToolCallUpdate: "struct"
  AgentRunnerError: "enum"

Helpers:
  ProjectTasksStorage: "tasks.json + screenshots per project"
  ProjectTask: "Identifiable, Codable (in ProjectTasksStorage file)"
  ProjectSettingsStorage: "per-project settings"
  AppPreferences: "UserDefaults preferences"
  WorkspaceHelpers: "path/workspace helpers"
  PreferredTerminalApp: "enum"
  TooltipModifier: "SwiftUI tooltip"

Theme:
  CursorTheme: "design tokens (see Views.Theme)"
  ModelOption: "struct"
  AvailableModels: "enum"
  QuickActionPrompts: "enum"
  AppLimits: "enum"
  MenuBarIcon: "enum"
  CursorAppIcon: "enum"
  BrandAppIconView: "View"
  BrandStatusIcon: "enum"
```

---

## Tasks, agent views & statuses (relationships)

**Data structure & cardinalities:**

```yaml
Project (workspace path):
  has many: Tasks          # ProjectTask in .metro/tasks.json
  has many: Conversations  # AgentTab with this workspacePath (tabs are global; association by path)

Task (ProjectTask):
  belongs to: one Project
  linked by: zero or one Conversation  # AgentTab.linkedTaskID

Conversation (AgentTab):
  belongs to: one Project  # workspacePath
  links to: zero or one Task  # linkedTaskID; drives LinkedTaskStatus on tab chip
  has one: conversationId   # cursorChatId, backend session id for --resume; persisted in SavedAgentTab
```

- **Tasks** (**ProjectTask**) live per project in **ProjectTasksStorage** (`.metro/tasks.json`). The **TasksListView** shows them for the selected project; you can add, edit, complete, and “send to agent.”
- **Agent tabs** (**AgentTab**) are conversations. An agent tab can be **linked** to a task via `linkedTaskID`; that link is what drives the status badge on the tab chip in the sidebar.
- **Task status** (**LinkedTaskStatus**: open, processing, done, stopped) is the *agent’s* view of the linked task: open = not started, processing = agent running, done = completed, stopped = run stopped. The sidebar **TabChip** shows this status (and **LightBlueSpinner** when running).
- **conversationId** — The Cursor backend’s ID for this chat session. On **AgentTab** it’s stored as **cursorChatId** (optional). Passed to **AgentRunner.stream(…, conversationId:)** as `--resume <id>` so the CLI continues the same conversation. Set when a run starts (from backend) and updated when a run ends; persisted in **SavedAgentTab** so conversations can be resumed after app restart.
- **Flow**: User picks a task in **TasksListView** → “Send to agent” creates or selects an **AgentTab** and sets its `linkedTaskID` → that tab’s chip shows **LinkedTaskStatus**; when the agent runs, status becomes processing, then done or stopped. Task completion (checkbox in Tasks list) is separate from “agent done”; both can exist for the same task.

---

## Summary

- **App**: `CursorPlusApp` → **AppDelegate** owns **FloatingPanel** and **AppState**; panel hosts **PopoutView**.
- **State**: **TabManager** owns projects, **AgentTab**/ **TerminalTab**, and selection; persisted via **TabManagerPersistence** and **SavedTabState**.
- **Models**: Conversation (**ConversationTurn**, segments, stream phase), tasks (**ProjectTask**), and agent streaming (**AgentStreamChunk**, **AgentToolCallUpdate**).
- **Views**: **PopoutView** = sidebar (tab chips, workspace/branch pickers) + main content (Tasks list or agent UI or terminal). Agent UI = top bar + composer + output (conversation + screenshots). Settings and quick actions are separate flows.
- **Services**: **AgentRunner** runs CLI and parses stream.
- **Helpers**: **ProjectTasksStorage**, **ProjectSettingsStorage**, **AppPreferences**, **WorkspaceHelpers**.
- **Theme**: **CursorTheme**, model/limits/prompts enums, and branding views in App/Theme.
