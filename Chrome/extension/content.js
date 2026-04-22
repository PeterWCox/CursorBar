(function bootstrap() {
  if (window.__iltmInjected) {
    return;
  }
  window.__iltmInjected = true;

  const DEFAULT_BRIDGE = "http://127.0.0.1:4317";
  /** Same values as macOS `AgentProviderID` / bridge `normalizeProviderId`. */
  const PROVIDER_CURSOR = "cursor";
  const PROVIDER_CLAUDE_CODE = "claudeCode";
  /** Same asset as Cursor Metro `CursorMetroLogo` in `Assets.xcassets`, bundled under `extension/assets/`. */
  const CURSOR_METRO_LOGO_URL = chrome.runtime.getURL("assets/cursor-metro-logo.png");
  const storageKey = "iltmState";
  /** Legacy Chrome-only task list; tasks now live in `.metro/tasks.json` like the macOS app. */
  const legacyTasksStorageKey = "iltmTasksV1";

  const QUICK_ACTION_COMMIT_PUSH = `Review the current git changes (e.g. git status and diff). Summarise them in a single, clear commit message and create one atomic commit, then push to the current branch. Only commit if the changes look intentional and ready to ship.`;

  const QUICK_ACTION_FIX_BUILD = `Fix the build. Identify and fix any compile errors, test failures, or other issues preventing the project from building successfully. Run the build (and tests if applicable) and iterate until everything passes.`;

  function normalizeProviderId(raw) {
    const s = String(raw || PROVIDER_CLAUDE_CODE).trim();
    if (s === PROVIDER_CLAUDE_CODE || s.toLowerCase() === "claude" || s.toLowerCase() === "claudecode") {
      return PROVIDER_CLAUDE_CODE;
    }
    return PROVIDER_CURSOR;
  }

  function metroAppMarketingName(providerId) {
    return normalizeProviderId(providerId) === PROVIDER_CLAUDE_CODE ? "Claude Metro" : "Cursor Metro";
  }

  /** @type {{ streamParts: StreamPart[], sessionModelLabel: string | null, visible: boolean, panelOpen: boolean, running: boolean, requestId: string, sessionId: string, workspacePath: string, savedProjects: Array<{path:string,label:string}>, recentProjects: string[], modelId: string, models: Array<{id:string,label:string}>, statusText: string, statusTone: string, bridgeBaseUrl: string, agentProviderId: string, metroTasksByWorkspace: Record<string, MetroProjectTask[]>, tasksListTab: 'backlog' | 'inProgress' | 'completed' | 'deleted', taskComposerOpen: boolean, newTaskDraft: string, newTaskModelId: string, newTaskTargetState: 'backlog' | 'inProgress', newTaskScreenshotsBase64: string[], composerPastePngBase64: string[], editingTaskId: string | null, editingTaskDraft: string, openTaskMenuId: string | null, selectedTaskId: string | null, sidebarFocus: 'agent' | 'tasks', mainColumnMode: 'agent' | 'tasks', settingsOpen: boolean, activeProjectForTasks: string, messageQueue: Array<{ workspacePath: string, modelId: string, prompt: string, providerId: string, taskScreenshotPaths: string[], extraScreenshotPngBase64: string[] }> }} */
  const state = {
    /** @type {StreamPart[]} — chronological segments (same order as Cursor Metro conversation stream). */
    streamParts: [],
    sessionModelLabel: null,
    visible: false,
    panelOpen: false,
    running: false,
    requestId: "",
    sessionId: "",
    workspacePath: "",
    savedProjects: [],
    recentProjects: [],
    modelId: "auto",
    models: [],
    statusText: "Click the extension icon to open Metro.",
    statusTone: "neutral",
    bridgeBaseUrl: DEFAULT_BRIDGE,
    agentProviderId: PROVIDER_CLAUDE_CODE,
    /** @type {Record<string, MetroProjectTask[]>} normalized workspace path → tasks from `.metro/tasks.json`. */
    metroTasksByWorkspace: {},
    tasksListTab: "inProgress",
    taskComposerOpen: false,
    newTaskDraft: "",
    newTaskModelId: "auto",
    newTaskTargetState: "inProgress",
    newTaskScreenshotsBase64: [],
    composerPastePngBase64: [],
    editingTaskId: null,
    editingTaskDraft: "",
    openTaskMenuId: null,
    selectedTaskId: null,
    sidebarFocus: "agent",
    mainColumnMode: "agent",
    settingsOpen: false,
    activeProjectForTasks: "",
    /** Follow-up sends while `running`; each item omits `sessionId` so the next run uses the latest session after the prior turn completes. */
    messageQueue: [],
  };

  /**
   * @typedef {{ id: string, content: string, createdAt: number, taskState?: string, completed?: boolean, deleted?: boolean, backlog?: boolean, completedAt?: number | null, deletedAt?: number | null, screenshotPaths?: string[], providerID?: string, modelId?: string, preDeletionTaskState?: string | null }} MetroProjectTask
   * @typedef {{ type: 'thinking', text: string, completed: boolean } | { type: 'tool', callId: string, title: string, detail: string, status: string } | { type: 'assistant', text: string }} StreamPart
   */

  const root = document.createElement("div");
  root.id = "iltm-root";
  root.classList.add("iltm-hidden");

  const launcher = document.createElement("button");
  launcher.className = "iltm-launcher";
  launcher.type = "button";
  launcher.textContent = "+";
  launcher.title = "Open Metro";

  const panel = document.createElement("section");
  panel.className = "iltm-panel iltm-hidden";

  panel.innerHTML = `
    <div class="iltm-shell">
      <div class="iltm-main">
        <div class="iltm-main-header">
          <div class="iltm-main-title-block">
            <div class="iltm-title" data-role="main-title">Claude Metro</div>
            <div class="iltm-subtle" data-role="main-subtitle">In-tab agent — Cursor or Claude Code CLI, same as the macOS app.</div>
          </div>
        </div>
        <div class="iltm-status" data-role="status">Checking bridge status...</div>

        <div class="iltm-main-agent" data-role="main-agent">
          <div class="iltm-stream-wrap">
            <div class="iltm-stream" data-role="stream"></div>
          </div>
          <div class="iltm-composer">
            <div class="iltm-quick-actions" aria-label="Quick actions">
              <button type="button" class="iltm-pill" data-action="quick-fix-build" title="Same as Cursor Metro">Fix build</button>
              <button type="button" class="iltm-pill" data-action="quick-commit-push" title="Same as Cursor Metro">Commit &amp; push</button>
              <button type="button" class="iltm-pill iltm-pill--ghost" data-action="scroll-stream-top" title="Scroll to top of this run">Show history</button>
              <button
                type="button"
                class="iltm-pill iltm-pill--ghost"
                data-action="paste-screenshot-composer"
                title="Read an image from the clipboard (when ⌘V is captured by the host page)"
              >
                Paste screenshot
              </button>
            </div>
            <textarea class="iltm-textarea" data-role="prompt" placeholder="⌘V to paste screenshots, ⇧Enter for new line, Enter to send."></textarea>
            <div class="iltm-composer-footer">
              <div class="iltm-composer-footer-row">
                <select class="iltm-select iltm-select--footer" data-role="model"></select>
                <button type="button" class="iltm-footer-refresh" data-action="refresh-models" title="Refresh models">↻</button>
                <span class="iltm-footer-branch" data-role="footer-branch">—</span>
                <span class="iltm-footer-spinner" data-role="footer-spinner"></span>
                <span class="iltm-footer-cost">$???</span>
              </div>
              <div class="iltm-composer-footer-row iltm-composer-footer-row--buttons">
                <button type="button" class="iltm-button iltm-button--primary" data-action="send">Send</button>
                <button type="button" class="iltm-button iltm-button--ghost" data-action="stop">Stop</button>
                <button type="button" class="iltm-button iltm-button--ghost" data-action="new-chat">New chat</button>
              </div>
            </div>
          </div>
        </div>

        <div class="iltm-main-tasks iltm-hidden" data-role="main-tasks">
          <div class="iltm-tasks-toolbar">
            <button type="button" class="iltm-button iltm-button--primary iltm-button--small" data-action="toggle-task-composer">Add task</button>
            <button type="button" class="iltm-pill" data-action="tasks-quick-commit">Commit &amp; push</button>
            <button type="button" class="iltm-pill" data-action="tasks-quick-fix">Fix build</button>
          </div>
          <div class="iltm-tasks-tabs" data-role="tasks-tabs"></div>
          <div class="iltm-new-task-panel iltm-hidden" data-role="new-task-panel">
            <textarea class="iltm-textarea iltm-textarea--task" data-role="new-task-input" rows="3" placeholder="Describe the task — ⌘V to paste screenshots (same as Cursor Metro)."></textarea>
            <div class="iltm-new-task-attach">
              <button
                type="button"
                class="iltm-pill iltm-pill--ghost iltm-pill--compact"
                data-action="paste-screenshot-new-task"
                title="Read an image from the clipboard (when ⌘V is captured by the host page)"
              >
                Paste screenshot
              </button>
            </div>
            <div class="iltm-new-task-row">
              <label class="iltm-label-inline">Model</label>
              <select class="iltm-select iltm-select--small" data-role="new-task-model"></select>
              <div class="iltm-segment" aria-label="Task list when saved">
                <button type="button" class="iltm-segment-btn iltm-segment-btn--on" data-action="new-task-state" data-state="inProgress">In progress</button>
                <button type="button" class="iltm-segment-btn" data-action="new-task-state" data-state="backlog">Backlog</button>
              </div>
            </div>
            <div class="iltm-new-task-shots" data-role="new-task-shots"></div>
            <div class="iltm-new-task-actions">
              <button type="button" class="iltm-button iltm-button--primary iltm-button--small" data-action="commit-new-task">Save task</button>
              <button type="button" class="iltm-button iltm-button--ghost iltm-button--small" data-action="cancel-new-task">Cancel</button>
            </div>
          </div>
          <div class="iltm-task-list" data-role="tasks-board"></div>
        </div>
      </div>

      <aside class="iltm-sidebar">
        <div class="iltm-sidebar-top">
          <div class="iltm-brand">
            <span class="iltm-brand-mark" data-role="brand-mark">Claude Metro</span>
            <span class="iltm-beta">BETA</span>
          </div>
          <div class="iltm-sidebar-actions">
            <button type="button" class="iltm-icon-btn" data-action="open-settings" title="Settings">⚙</button>
            <button type="button" class="iltm-icon-btn" data-action="close" title="Close">−</button>
          </div>
        </div>
        <div class="iltm-sidebar-heading">Projects</div>
        <div class="iltm-sidebar-scroll" data-role="sidebar-projects"></div>
        <div class="iltm-sidebar-footer">
          <button type="button" class="iltm-sidebar-import" data-action="pick-workspace">Import</button>
          <button type="button" class="iltm-sidebar-create" data-action="create-hint" title="Scaffold and Preview are available in the Cursor Metro macOS app">Create</button>
        </div>
      </aside>
    </div>

    <div class="iltm-settings iltm-hidden" data-role="settings-overlay">
      <div class="iltm-settings-card">
        <div class="iltm-settings-header">
          <span>Settings</span>
          <button type="button" class="iltm-button iltm-button--ghost iltm-button--small" data-action="close-settings">Close</button>
        </div>
        <label class="iltm-label">Agent backend</label>
        <select class="iltm-select" data-role="agent-provider">
          <option value="${PROVIDER_CLAUDE_CODE}">Claude Code (<code>claude</code>)</option>
          <option value="${PROVIDER_CURSOR}">Cursor (<code>agent</code>)</option>
        </select>
        <p class="iltm-subtle">Same provider IDs as the macOS app (<code>claudeCode</code> / <code>cursor</code>). After switching, use <strong>New chat</strong> so session IDs match the CLI you use.</p>
        <label class="iltm-label">Bridge base URL</label>
        <input type="url" class="iltm-input" data-role="bridge-url" placeholder="http://127.0.0.1:4317" />
        <p class="iltm-subtle">Must match the local bridge (<code>npm start</code> in <code>CursorMetro/Chrome</code>). Reload models after changing.</p>
        <button type="button" class="iltm-button iltm-button--primary" data-action="save-settings">Save</button>
      </div>
    </div>
  `;

  root.appendChild(panel);
  root.appendChild(launcher);
  document.documentElement.appendChild(root);

  const statusEl = panel.querySelector('[data-role="status"]');
  const streamEl = panel.querySelector('[data-role="stream"]');
  const modelEl = panel.querySelector('[data-role="model"]');
  const promptEl = panel.querySelector('[data-role="prompt"]');
  const sendButton = panel.querySelector('[data-action="send"]');
  const stopButton = panel.querySelector('[data-action="stop"]');
  const mainTitleEl = panel.querySelector('[data-role="main-title"]');
  const mainSubtitleEl = panel.querySelector('[data-role="main-subtitle"]');
  const mainAgentEl = panel.querySelector('[data-role="main-agent"]');
  const mainTasksEl = panel.querySelector('[data-role="main-tasks"]');
  const tasksBoardEl = panel.querySelector('[data-role="tasks-board"]');
  const sidebarProjectsEl = panel.querySelector('[data-role="sidebar-projects"]');
  const settingsOverlay = panel.querySelector('[data-role="settings-overlay"]');
  const bridgeUrlInput = panel.querySelector('[data-role="bridge-url"]');
  const agentProviderSelect = panel.querySelector('[data-role="agent-provider"]');
  const brandMarkEl = panel.querySelector('[data-role="brand-mark"]');
  const footerBranchEl = panel.querySelector('[data-role="footer-branch"]');
  const footerSpinnerEl = panel.querySelector('[data-role="footer-spinner"]');
  const tasksTabsEl = panel.querySelector('[data-role="tasks-tabs"]');
  const newTaskPanelEl = panel.querySelector('[data-role="new-task-panel"]');
  const newTaskInputEl = panel.querySelector('[data-role="new-task-input"]');
  const newTaskModelEl = panel.querySelector('[data-role="new-task-model"]');
  const newTaskShotsEl = panel.querySelector('[data-role="new-task-shots"]');

  let eventSource = null;
  let streamRaf = null;

  function bridgeUrl() {
    const u = String(state.bridgeBaseUrl || "").trim();
    return u || DEFAULT_BRIDGE;
  }

  function normalizePath(p) {
    return String(p || "")
      .trim()
      .replace(/\/+$/, "");
  }

  function allProjectPaths() {
    const set = new Set();
    for (const s of state.savedProjects) {
      if (s.path) {
        set.add(normalizePath(s.path));
      }
    }
    for (const r of state.recentProjects) {
      if (r) {
        set.add(normalizePath(r));
      }
    }
    if (state.workspacePath) {
      set.add(normalizePath(state.workspacePath));
    }
    return [...set].filter(Boolean);
  }

  function projectLabel(path) {
    const hit = state.savedProjects.find((s) => normalizePath(s.path) === normalizePath(path));
    if (hit?.label) {
      return hit.label;
    }
    return basenamePath(path);
  }

  function hueForPath(path) {
    let h = 0;
    const s = String(path);
    for (let i = 0; i < s.length; i++) {
      h = (h + s.charCodeAt(i) * 17) % 360;
    }
    return h;
  }

  function appendThinkingDelta(text) {
    const last = state.streamParts[state.streamParts.length - 1];
    if (last && last.type === "thinking" && !last.completed) {
      last.text += text || "";
    } else {
      state.streamParts.push({ type: "thinking", text: text || "", completed: false });
    }
  }

  function completeThinking() {
    const last = state.streamParts[state.streamParts.length - 1];
    if (last && last.type === "thinking") {
      last.completed = true;
    }
  }

  function upsertTool(data) {
    const idx = state.streamParts.findIndex((p) => p.type === "tool" && p.callId === data.callId);
    const row = {
      type: "tool",
      callId: data.callId,
      title: data.title || "Tool",
      detail: data.detail || "",
      status: data.status || "started",
    };
    if (idx >= 0) {
      state.streamParts[idx] = row;
    } else {
      state.streamParts.push(row);
    }
  }

  function appendAssistantDelta(text) {
    if (!text) {
      return;
    }
    const last = state.streamParts[state.streamParts.length - 1];
    if (last && last.type === "assistant") {
      last.text += text;
    } else {
      state.streamParts.push({ type: "assistant", text });
    }
  }

  function scheduleStreamRender() {
    if (streamRaf) {
      return;
    }
    streamRaf = requestAnimationFrame(() => {
      streamRaf = null;
      renderStreamFromState();
    });
  }

  function toolBadge(status) {
    const s = String(status || "").toLowerCase();
    if (s === "failed" || s.includes("fail")) {
      return "Failed";
    }
    if (s === "completed" || s === "done") {
      return "Done";
    }
    return "Running";
  }

  function renderStreamFromState() {
    if (!streamEl) {
      return;
    }
    if (!state.streamParts.length) {
      streamEl.innerHTML = `<div class="iltm-stream-placeholder">Output streams here in real time (thinking, tools, assistant) — same JSON stream as Cursor Metro.</div>`;
      return;
    }

    const html = state.streamParts
      .map((part) => {
        if (part.type === "thinking") {
          const icon = part.completed
            ? `<span class="iltm-seg-icon iltm-seg-icon--done">✓</span>`
            : `<span class="iltm-thinking-dots" aria-hidden="true"><span></span><span></span><span></span></span>`;
          return `<div class="iltm-seg-card iltm-seg-thinking">
            <div class="iltm-seg-thinking-head">
              ${icon}
              <span class="iltm-seg-thinking-title">Thinking</span>
              <span class="iltm-seg-chevron">›</span>
            </div>
            <pre class="iltm-seg-thinking-body">${escapeHtml(part.text || "")}</pre>
          </div>`;
        }
        if (part.type === "tool") {
          const badge = toolBadge(part.status);
          const badgeClass =
            badge === "Done" ? "iltm-seg-badge--done" : badge === "Failed" ? "iltm-seg-badge--fail" : "iltm-seg-badge--run";
          return `<div class="iltm-seg-card iltm-seg-tool">
            <div class="iltm-seg-tool-top">
              <span class="iltm-seg-tool-title">${escapeHtml(part.title)}</span>
              <span class="iltm-seg-badge ${badgeClass}">${escapeHtml(badge)}</span>
            </div>
            <div class="iltm-seg-tool-detail">${escapeHtml(part.detail || "")}</div>
          </div>`;
        }
        if (part.type === "assistant") {
          return `<div class="iltm-seg-assistant"><pre>${escapeHtml(part.text)}</pre></div>`;
        }
        return "";
      })
      .join("");

    streamEl.innerHTML = html;
    streamEl.scrollTop = streamEl.scrollHeight;
  }

  async function loadPersistedState() {
    const stored = await chrome.storage.local.get([storageKey, legacyTasksStorageKey]);
    const saved = stored[storageKey] || {};
    state.workspacePath = saved.workspacePath || "";
    state.recentProjects = Array.isArray(saved.recentProjects) ? saved.recentProjects : [];
    state.modelId = saved.modelId || "auto";
    state.newTaskModelId = state.modelId;
    state.sessionId = saved.sessionId || "";
    state.bridgeBaseUrl = typeof saved.bridgeBaseUrl === "string" && saved.bridgeBaseUrl.trim() ? saved.bridgeBaseUrl.trim() : DEFAULT_BRIDGE;
    state.agentProviderId = normalizeProviderId(saved.agentProviderId);
    if (stored[legacyTasksStorageKey]) {
      await chrome.storage.local.remove([legacyTasksStorageKey]);
    }
    if (state.workspacePath && !state.activeProjectForTasks) {
      state.activeProjectForTasks = state.workspacePath;
    }
    render();
  }

  async function persistState() {
    await chrome.storage.local.set({
      [storageKey]: {
        workspacePath: state.workspacePath,
        recentProjects: state.recentProjects,
        modelId: state.modelId,
        sessionId: state.sessionId,
        bridgeBaseUrl: state.bridgeBaseUrl,
        agentProviderId: state.agentProviderId,
      },
    });
  }

  function setStatus(text, tone = "neutral") {
    state.statusText = text;
    state.statusTone = tone;
    if (statusEl) {
      statusEl.textContent = text;
      statusEl.dataset.tone = tone;
    }
  }

  function taskStateOf(t) {
    if (t && typeof t.taskState === "string" && t.taskState) {
      return t.taskState;
    }
    if (t && t.deleted) {
      return "deleted";
    }
    if (t && t.completed) {
      return "completed";
    }
    if (t && t.backlog) {
      return "backlog";
    }
    return "inProgress";
  }

  function numTime(v) {
    if (v == null) {
      return 0;
    }
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }

  function metroAssetUrl(ws, relPath) {
    const base = bridgeUrl();
    return `${base}/api/metro-asset?workspacePath=${encodeURIComponent(ws)}&path=${encodeURIComponent(relPath)}`;
  }

  function tasksForWorkspace(ws) {
    const n = normalizePath(ws);
    return state.metroTasksByWorkspace[n] || [];
  }

  function sidebarTasks(ws) {
    return tasksForWorkspace(ws).filter((t) => {
      const s = taskStateOf(t);
      return s === "inProgress" || s === "backlog";
    });
  }

  function boardTasksForTab(ws, tab) {
    return tasksForWorkspace(ws).filter((t) => taskStateOf(t) === tab);
  }

  function sortBoardTasks(tab, list) {
    const arr = list.slice();
    if (tab === "completed") {
      return arr.sort((a, b) => numTime(b.completedAt) - numTime(a.completedAt));
    }
    if (tab === "deleted") {
      return arr.sort((a, b) => numTime(b.deletedAt) - numTime(a.deletedAt));
    }
    return arr.sort((a, b) => numTime(b.createdAt) - numTime(a.createdAt));
  }

  function countTasksForTab(ws, tab) {
    return boardTasksForTab(ws, tab).length;
  }

  async function refreshMetroTasks(ws) {
    const raw = ws || state.activeProjectForTasks || state.workspacePath;
    const n = normalizePath(raw);
    if (!n) {
      render();
      return;
    }
    try {
      const response = await fetch(`${bridgeUrl()}/api/metro-tasks?workspacePath=${encodeURIComponent(raw)}`);
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load tasks.");
      }
      state.metroTasksByWorkspace[n] = Array.isArray(data.tasks) ? data.tasks : [];
    } catch {
      state.metroTasksByWorkspace[n] = [];
    }
    render();
  }

  async function refreshTasksForVisibleProjects() {
    const paths = allProjectPaths();
    await Promise.all(paths.map((p) => refreshMetroTasks(p)));
  }

  async function patchMetroTask(workspacePath, id, patch) {
    const response = await fetch(`${bridgeUrl()}/api/metro-tasks`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ workspacePath, id, ...patch }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      throw new Error(data.error || "Could not update task.");
    }
    return data.task;
  }

  async function createMetroTaskOnBridge(workspacePath, body) {
    const response = await fetch(`${bridgeUrl()}/api/metro-tasks`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ workspacePath, ...body }),
    });
    const data = await response.json();
    if (!response.ok || !data.ok) {
      throw new Error(data.error || "Could not create task.");
    }
    return data.task;
  }

  function renderSidebar() {
    if (!sidebarProjectsEl) {
      return;
    }
    const paths = allProjectPaths();
    if (!paths.length) {
      sidebarProjectsEl.innerHTML = `<div class="iltm-sidebar-empty">No projects yet. Use <strong>Import</strong> or add entries in the bridge <code>projects.json</code>.</div>`;
      return;
    }

    const blocks = paths.map((path) => {
      const label = escapeHtml(projectLabel(path));
      const hue = hueForPath(path);
      const isSelected = normalizePath(state.workspacePath) === normalizePath(path);
      const tasksPage = state.mainColumnMode === "tasks" && normalizePath(state.activeProjectForTasks) === normalizePath(path);
      const taskRows = sidebarTasks(path)
        .slice()
        .sort((a, b) => numTime(b.createdAt) - numTime(a.createdAt))
        .map((t) => {
          const run = state.running && state.selectedTaskId === t.id;
          const active = state.selectedTaskId === t.id && !state.running;
          const cls = ["iltm-sidebar-task"];
          if (run) {
            cls.push("iltm-sidebar-task--run");
          }
          if (active) {
            cls.push("iltm-sidebar-task--active");
          }
          return `
            <div class="${cls.join(" ")}" data-action="select-task" data-task-id="${escapeHtml(t.id)}" data-workspace="${escapeHtml(path)}">
              <span class="iltm-sidebar-task-dot" style="background:hsl(${hue},70%,52%)"></span>
              <span class="iltm-sidebar-task-title">${escapeHtml(truncate(t.content || "", 42))}</span>
              <button type="button" class="iltm-sidebar-task-x" data-action="sidebar-task-delete" data-task-id="${escapeHtml(t.id)}" data-workspace="${escapeHtml(path)}" title="Move to Deleted">×</button>
            </div>`;
        })
        .join("");

      return `
        <div class="iltm-project-group ${isSelected ? "iltm-project-group--selected" : ""}" data-path="${escapeHtml(path)}">
          <div class="iltm-project-head">
            <button type="button" class="iltm-project-select" data-action="select-project" data-path="${escapeHtml(path)}">
              <img class="iltm-avatar iltm-avatar--logo" src="${CURSOR_METRO_LOGO_URL}" alt="" width="28" height="28" />
              <span class="iltm-project-meta">
                <span class="iltm-project-name">${label}</span>
                <span class="iltm-project-branch"></span>
              </span>
            </button>
          </div>
          <div class="iltm-project-pages">
            <button type="button" class="iltm-page-chip ${tasksPage ? "iltm-page-chip--on" : ""}" data-action="show-tasks-page" data-path="${escapeHtml(path)}">Tasks</button>
            <button type="button" class="iltm-page-chip iltm-page-chip--disabled" disabled title="Preview terminals run in the Cursor Metro app">Preview</button>
          </div>
          <div class="iltm-project-tasks">${taskRows}</div>
        </div>`;
    });

    sidebarProjectsEl.innerHTML = blocks.join("");
  }

  function renderTaskTabs() {
    if (!tasksTabsEl) {
      return;
    }
    const ws = state.activeProjectForTasks || state.workspacePath;
    if (!ws || state.mainColumnMode !== "tasks") {
      tasksTabsEl.innerHTML = "";
      return;
    }
    const tabs = [
      { id: "backlog", label: "Backlog" },
      { id: "inProgress", label: "In progress" },
      { id: "completed", label: "Completed" },
      { id: "deleted", label: "Deleted" },
    ];
    tasksTabsEl.innerHTML = tabs
      .map((tab) => {
        const c = countTasksForTab(ws, tab.id);
        const on = state.tasksListTab === tab.id;
        return `<button type="button" class="iltm-tab${on ? " iltm-tab--on" : ""}" data-action="tasks-tab" data-tab="${tab.id}">${escapeHtml(tab.label)} <span class="iltm-tab-n">${c}</span></button>`;
      })
      .join("");
  }

  function renderNewTaskPanel() {
    if (!newTaskPanelEl) {
      return;
    }
    newTaskPanelEl.classList.toggle("iltm-hidden", !state.taskComposerOpen);
    if (newTaskInputEl) {
      newTaskInputEl.value = state.newTaskDraft;
    }
    for (const btn of newTaskPanelEl.querySelectorAll('[data-action="new-task-state"]')) {
      const st = btn.getAttribute("data-state");
      btn.classList.toggle("iltm-segment-btn--on", st === state.newTaskTargetState);
    }
    if (newTaskModelEl) {
      newTaskModelEl.innerHTML = "";
      const opts = state.models.length ? state.models : [{ id: "auto", label: "Auto" }];
      for (const model of opts) {
        const option = document.createElement("option");
        option.value = model.id;
        option.textContent = `${model.label} (${model.id})`;
        option.selected = model.id === state.newTaskModelId;
        newTaskModelEl.appendChild(option);
      }
    }
    if (newTaskShotsEl) {
      newTaskShotsEl.innerHTML = state.newTaskScreenshotsBase64
        .map(
          (b64, i) => `<div class="iltm-shot-thumb-wrap">
          <img class="iltm-shot-thumb" alt="" src="data:image/png;base64,${b64}" />
          <button type="button" class="iltm-shot-rm" data-action="remove-new-task-shot" data-index="${i}">×</button>
        </div>`,
        )
        .join("");
    }
  }

  function taskCardHtml(t, ws) {
    const id = String(t.id);
    const st = taskStateOf(t);
    const isEditing = state.editingTaskId === id;
    const shots = (t.screenshotPaths || [])
      .slice(0, 6)
      .map(
        (p) =>
          `<img class="iltm-task-shot" alt="" loading="lazy" src="${escapeHtml(metroAssetUrl(ws, p))}" />`,
      )
      .join("");

    const editBlock = isEditing
      ? `<textarea class="iltm-textarea iltm-textarea--taskedit" data-role="inline-edit" data-task-id="${escapeHtml(id)}" rows="4">${escapeHtml(state.editingTaskDraft)}</textarea>
        <div class="iltm-inline-edit-actions">
          <button type="button" class="iltm-button iltm-button--primary iltm-button--small" data-action="save-inline-task" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}">Save</button>
          <button type="button" class="iltm-button iltm-button--ghost iltm-button--small" data-action="cancel-inline-task">Cancel</button>
        </div>`
      : `<div class="iltm-task-card-body">${escapeHtml(truncate(t.content || "", 800))}</div>
        <div class="iltm-task-shots">${shots}</div>
        <div class="iltm-task-meta">
          <span class="iltm-task-chip">${escapeHtml(String(t.modelId || "auto"))}</span>
          <span class="iltm-task-chip">${escapeHtml(normalizeProviderId(t.providerID))}</span>
        </div>`;

    const items = [];
    if ((st === "inProgress" || st === "backlog") && !state.running) {
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="send-task" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}">Send to agent</button>`,
      );
    }
    if (st === "inProgress" || st === "backlog") {
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="edit-task" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}">Edit…</button>`,
      );
    }
    items.push('<div class="iltm-menu-sep"></div>');
    if (st === "inProgress") {
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="patch-task-move" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}" data-to="backlog">Move to backlog</button>`,
      );
    }
    if (st === "backlog" || st === "completed") {
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="patch-task-move" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}" data-to="inProgress">Move to in progress</button>`,
      );
    }
    if (st !== "completed" && st !== "deleted") {
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="patch-task-move" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}" data-to="completed">Mark completed</button>`,
      );
    }
    if (st !== "deleted") {
      items.push(
        `<button type="button" class="iltm-menu-item iltm-menu-item--danger" data-action="patch-task-move" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}" data-to="deleted">Move to deleted</button>`,
      );
    }
    if (st === "deleted" && t.preDeletionTaskState) {
      const restore = String(t.preDeletionTaskState);
      items.push(
        `<button type="button" class="iltm-menu-item" data-action="patch-task-move" data-task-id="${escapeHtml(id)}" data-workspace="${escapeHtml(ws)}" data-to="${escapeHtml(restore)}">Restore</button>`,
      );
    }

    return `<div class="iltm-task-card" data-task-id="${escapeHtml(id)}">
      <div class="iltm-task-card-top">
        <div class="iltm-task-card-main">${editBlock}</div>
        <details class="iltm-task-menu">
          <summary class="iltm-task-dots" aria-label="Task actions">⋯</summary>
          <div class="iltm-task-menu-panel">${items.join("")}</div>
        </details>
      </div>
    </div>`;
  }

  function renderTasksBoard() {
    if (!tasksBoardEl) {
      return;
    }
    const ws = state.activeProjectForTasks || state.workspacePath;
    if (!ws) {
      tasksBoardEl.innerHTML = `<div class="iltm-subtle">Select a project in the sidebar.</div>`;
      return;
    }
    const tab = state.tasksListTab;
    const list = sortBoardTasks(tab, boardTasksForTab(ws, tab));
    if (!list.length) {
      const labels = { backlog: "Backlog", inProgress: "In progress", completed: "Completed", deleted: "Deleted" };
      const lab = labels[tab] || tab;
      tasksBoardEl.innerHTML = `<div class="iltm-tasks-empty">No tasks in <strong>${escapeHtml(lab)}</strong> for <strong>${escapeHtml(basenamePath(ws))}</strong>. Add a task or switch tabs.</div>`;
      return;
    }
    tasksBoardEl.innerHTML = list.map((t) => taskCardHtml(t, ws)).join("");
  }

  function renderMainHeaders() {
    if (state.mainColumnMode === "tasks") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      mainTitleEl.textContent = "Tasks";
      mainSubtitleEl.textContent = ws ? basenamePath(ws) : "";
      return;
    }
    if (state.selectedTaskId) {
      const ws = state.workspacePath;
      const task = tasksForWorkspace(ws).find((t) => String(t.id) === String(state.selectedTaskId));
      if (task) {
        mainTitleEl.textContent = truncate(task.content || "", 72);
        mainSubtitleEl.textContent = projectLabel(ws);
        return;
      }
    }
    mainTitleEl.textContent = metroAppMarketingName(state.agentProviderId);
    mainSubtitleEl.textContent = state.workspacePath ? basenamePath(state.workspacePath) : "Select a project in the sidebar.";
  }

  function updateFooterChrome() {
    if (footerBranchEl) {
      footerBranchEl.textContent = state.workspacePath ? truncate(basenamePath(state.workspacePath), 24) : "—";
    }
    if (footerSpinnerEl) {
      footerSpinnerEl.classList.toggle("iltm-footer-spinner--on", state.running);
    }
  }

  function render() {
    root.classList.toggle("iltm-hidden", !state.visible);
    panel.classList.toggle("iltm-hidden", !state.panelOpen);
    launcher.title = `Open ${metroAppMarketingName(state.agentProviderId)}`;
    if (brandMarkEl) {
      brandMarkEl.textContent = metroAppMarketingName(state.agentProviderId);
    }
    if (agentProviderSelect) {
      agentProviderSelect.value = state.agentProviderId;
    }
    promptEl.disabled = false;
    modelEl.disabled = false;
    sendButton.disabled = false;
    sendButton.textContent = state.running ? "Queue" : "Send";
    sendButton.title = state.running
      ? "Add this message to the queue (sent after the current run finishes)."
      : "Send to the agent.";
    stopButton.disabled = !state.running;

    for (const pill of panel.querySelectorAll(".iltm-pill")) {
      pill.disabled = false;
    }

    renderSidebar();
    renderTaskTabs();
    renderNewTaskPanel();
    renderTasksBoard();
    renderMainHeaders();
    updateFooterChrome();

    mainAgentEl.classList.toggle("iltm-hidden", state.mainColumnMode !== "agent");
    mainTasksEl.classList.toggle("iltm-hidden", state.mainColumnMode !== "tasks");

    if (statusEl) {
      statusEl.textContent = state.statusText;
      statusEl.dataset.tone = state.statusTone;
    }

    modelEl.innerHTML = "";
    for (const model of state.models) {
      const option = document.createElement("option");
      option.value = model.id;
      option.textContent = `${model.label} (${model.id})`;
      option.selected = model.id === state.modelId;
      modelEl.appendChild(option);
    }
    if (!state.models.length) {
      const option = document.createElement("option");
      option.value = "auto";
      option.textContent = "Auto";
      modelEl.appendChild(option);
    }

    renderStreamFromState();

    if (bridgeUrlInput) {
      bridgeUrlInput.value = state.bridgeBaseUrl;
    }
    settingsOverlay.classList.toggle("iltm-hidden", !state.settingsOpen);
  }

  function escapeHtml(text) {
    return String(text)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;");
  }

  function truncate(s, n) {
    const t = String(s);
    return t.length <= n ? t : `${t.slice(0, n - 1)}…`;
  }

  function basenamePath(p) {
    const parts = String(p)
      .replace(/\\/g, "/")
      .split("/")
      .filter(Boolean);
    return parts.length ? parts[parts.length - 1] : p;
  }

  function addRecent(projectPath) {
    const p = String(projectPath || "").trim();
    if (!p) {
      return;
    }
    state.recentProjects = [p, ...state.recentProjects.filter((x) => x !== p)].slice(0, 24);
  }

  async function loadProjects() {
    try {
      const response = await fetch(`${bridgeUrl()}/api/projects`);
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error("Bad response");
      }
      state.savedProjects = Array.isArray(data.projects) ? data.projects : [];
    } catch {
      state.savedProjects = [];
    }
    render();
  }

  async function checkHealth() {
    try {
      const response = await fetch(`${bridgeUrl()}/health`);
      if (!response.ok) {
        throw new Error("Bridge unavailable.");
      }
      setStatus("Bridge online. Select a project, then send — output streams live.", "success");
    } catch {
      setStatus("Bridge offline. Run `npm run dev` in CursorMetro/Chrome or `npm start` for bridge only (check Settings → URL).", "error");
    }
  }

  async function pickWorkspace() {
    if (state.running) {
      return;
    }
    try {
      setStatus("Choose a folder in Finder…", "neutral");
      const response = await fetch(`${bridgeUrl()}/api/pick-folder`, {
        method: "POST",
      });
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to pick folder.");
      }
      state.workspacePath = String(data.path || "").trim();
      addRecent(state.workspacePath);
      state.sidebarFocus = "agent";
      state.mainColumnMode = "agent";
      state.activeProjectForTasks = state.workspacePath;
      await persistState();
      setStatus("Project selected.", "success");
      void refreshMetroTasks(state.workspacePath);
      render();
    } catch (error) {
      setStatus(error.message || "Could not pick folder.", "error");
      render();
    }
  }

  async function loadModels() {
    try {
      const response = await fetch(
        `${bridgeUrl()}/api/models?provider=${encodeURIComponent(normalizeProviderId(state.agentProviderId))}`,
      );
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load models.");
      }

      state.models = data.models.length ? data.models : [{ id: "auto", label: "Auto" }];
      if (!state.models.some((model) => model.id === state.modelId)) {
        state.modelId = state.models[0].id;
      }
      if (!state.models.some((model) => model.id === state.newTaskModelId)) {
        state.newTaskModelId = state.models[0].id;
      }
      await persistState();
      render();
    } catch (error) {
      state.models = [{ id: "auto", label: "Auto" }];
      state.modelId = "auto";
      state.newTaskModelId = "auto";
      render();
      setStatus(error.message || "Failed to load models.", "error");
    }
  }

  function resetStreamState() {
    state.streamParts = [];
    state.sessionModelLabel = null;
    scheduleStreamRender();
  }

  function disconnectStream() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
  }

  function attachStream(requestId) {
    disconnectStream();
    eventSource = new EventSource(`${bridgeUrl()}/api/stream/${requestId}`);

    eventSource.addEventListener("session", async (event) => {
      const data = JSON.parse(event.data);
      state.sessionId = data.sessionId || state.sessionId;
      if (data.model) {
        state.sessionModelLabel = data.model;
      }
      await persistState();
      setStatus("Streaming…");
      scheduleStreamRender();
    });

    eventSource.addEventListener("assistant_delta", (event) => {
      const data = JSON.parse(event.data);
      appendAssistantDelta(data.text || "");
      scheduleStreamRender();
    });

    eventSource.addEventListener("thinking_delta", (event) => {
      const data = JSON.parse(event.data);
      appendThinkingDelta(data.text || "");
      scheduleStreamRender();
    });

    eventSource.addEventListener("thinking_completed", () => {
      completeThinking();
      scheduleStreamRender();
    });

    eventSource.addEventListener("tool_call", (event) => {
      const data = JSON.parse(event.data);
      upsertTool(data);
      scheduleStreamRender();
    });

    eventSource.addEventListener("status", (event) => {
      const data = JSON.parse(event.data);
      if (data.state === "started") {
        setStatus("Agent running…");
      }
    });

    eventSource.addEventListener("result", async (event) => {
      const data = JSON.parse(event.data);
      state.sessionId = data.sessionId || state.sessionId;
      await persistState();
      const last = state.streamParts[state.streamParts.length - 1];
      const hasAssistant = last?.type === "assistant" && String(last.text || "").trim().length > 0;
      if (!hasAssistant && data.result) {
        appendAssistantDelta(typeof data.result === "string" ? data.result : String(data.result));
      }
      setStatus("Run completed.", data.isError ? "error" : "success");
      scheduleStreamRender();
    });

    eventSource.addEventListener("run_error", (event) => {
      try {
        const data = JSON.parse(event.data);
        setStatus(data.message || "Stream failed.", "error");
      } catch {
        setStatus("Lost connection to the local bridge.", "error");
      }
      scheduleStreamRender();
    });

    eventSource.addEventListener("done", async () => {
      state.running = false;
      state.selectedTaskId = null;
      state.composerPastePngBase64 = [];
      await persistState();
      await Promise.all([refreshMetroTasks(state.workspacePath), refreshMetroTasks(state.activeProjectForTasks)]);
      render();
      disconnectStream();
      void drainMessageQueueAfterRun();
    });

    eventSource.onerror = () => {
      if (state.running) {
        state.running = false;
        state.selectedTaskId = null;
        setStatus("Stream disconnected.", "error");
        render();
      }
      disconnectStream();
    };
  }

  function tryEnqueueAgentRequest(options) {
    const ws = normalizePath(options.workspacePath);
    const trimmedPrompt = String(options.prompt || "").trim();
    const paths = Array.isArray(options.taskScreenshotPaths) ? options.taskScreenshotPaths : [];
    const extras = Array.isArray(options.extraScreenshotPngBase64) ? options.extraScreenshotPngBase64 : [];

    if (!ws) {
      setStatus("Select a project in the sidebar first.", "error");
      render();
      return false;
    }
    if (!trimmedPrompt && !paths.length && !extras.length) {
      setStatus("Enter a prompt first (or paste a screenshot).", "error");
      render();
      return false;
    }

    state.messageQueue.push({
      workspacePath: ws,
      modelId: String(options.modelId || "auto").trim() || "auto",
      prompt: trimmedPrompt,
      providerId: normalizeProviderId(options.providerId),
      taskScreenshotPaths: paths.map((p) => String(p)),
      extraScreenshotPngBase64: extras.slice(),
    });
    return true;
  }

  async function drainMessageQueueAfterRun() {
    if (state.running || !state.messageQueue.length) {
      return;
    }
    const next = state.messageQueue.shift();
    const started = await startAgentRequest({
      workspacePath: next.workspacePath,
      modelId: next.modelId,
      prompt: next.prompt,
      providerId: next.providerId,
      sessionId: state.sessionId,
      taskScreenshotPaths: next.taskScreenshotPaths,
      extraScreenshotPngBase64: next.extraScreenshotPngBase64,
    });
    if (!started) {
      state.messageQueue.unshift(next);
    }
  }

  async function runQuickAction(promptText) {
    if (state.running) {
      if (
        tryEnqueueAgentRequest({
          workspacePath: state.workspacePath,
          modelId: state.modelId,
          prompt: promptText,
          providerId: state.agentProviderId,
          taskScreenshotPaths: [],
          extraScreenshotPngBase64: [],
        })
      ) {
        setStatus(`Queued (${state.messageQueue.length} in queue).`, "neutral");
        render();
      }
      return;
    }
    promptEl.value = promptText;
    await sendPrompt();
  }

  const MAX_SCREENSHOTS = 8;

  async function runQuickTaskAndSend(ws, title, agentPrompt) {
    const w = normalizePath(ws);
    if (!w) {
      return;
    }
    if (state.running) {
      try {
        await createMetroTaskOnBridge(w, {
          content: title.trim() || "Task",
          taskState: "inProgress",
          modelId: state.modelId,
          providerId: state.agentProviderId,
          screenshotsPngBase64: [],
        });
        await refreshMetroTasks(w);
        state.workspacePath = w;
        state.activeProjectForTasks = w;
        addRecent(w);
        await persistState();
      } catch (error) {
        setStatus(error.message || "Quick task failed.", "error");
        render();
        return;
      }
      if (
        tryEnqueueAgentRequest({
          workspacePath: w,
          modelId: state.modelId,
          prompt: agentPrompt,
          providerId: state.agentProviderId,
          taskScreenshotPaths: [],
          extraScreenshotPngBase64: [],
        })
      ) {
        setStatus(`Queued (${state.messageQueue.length} in queue).`, "neutral");
        render();
      }
      return;
    }
    try {
      await createMetroTaskOnBridge(w, {
        content: title.trim() || "Task",
        taskState: "inProgress",
        modelId: state.modelId,
        providerId: state.agentProviderId,
        screenshotsPngBase64: [],
      });
      await refreshMetroTasks(w);
      state.workspacePath = w;
      state.activeProjectForTasks = w;
      addRecent(w);
      await persistState();
      await startAgentRequest({
        workspacePath: w,
        modelId: state.modelId,
        prompt: agentPrompt,
        providerId: state.agentProviderId,
        sessionId: state.sessionId,
        taskScreenshotPaths: [],
        extraScreenshotPngBase64: [],
      });
    } catch (error) {
      setStatus(error.message || "Quick task failed.", "error");
      render();
    }
  }

  async function startAgentRequest(options) {
    const {
      workspacePath,
      prompt,
      modelId,
      providerId,
      sessionId = state.sessionId,
      taskScreenshotPaths = [],
      extraScreenshotPngBase64 = [],
    } = options;

    const ws = String(workspacePath || "").trim();
    const trimmedPrompt = String(prompt || "").trim();
    const paths = Array.isArray(taskScreenshotPaths) ? taskScreenshotPaths : [];
    const extras = Array.isArray(extraScreenshotPngBase64) ? extraScreenshotPngBase64 : [];

    if (!ws) {
      setStatus("Select a project in the sidebar first.", "error");
      render();
      return false;
    }
    if (!trimmedPrompt && !paths.length && !extras.length) {
      setStatus("Enter a prompt first (or paste a screenshot).", "error");
      render();
      return false;
    }

    addRecent(ws);

    state.running = true;
    state.requestId = "";
    resetStreamState();
    setStatus("Starting agent…");
    await persistState();
    render();

    try {
      const response = await fetch(`${bridgeUrl()}/api/tasks`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          workspacePath: ws,
          modelId: modelId || "auto",
          prompt: trimmedPrompt,
          sessionId,
          providerId: normalizeProviderId(providerId),
          taskScreenshotPaths: paths,
          extraScreenshotPngBase64: extras,
        }),
      });
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to start task.");
      }

      state.requestId = data.requestId;
      attachStream(data.requestId);
      setStatus("Streaming…");
      return true;
    } catch (error) {
      state.running = false;
      state.selectedTaskId = null;
      setStatus(error.message || "Failed to start task.", "error");
      render();
      return false;
    }
  }

  async function sendPrompt() {
    state.modelId = modelEl.value || "auto";
    const prompt = promptEl.value.trim();
    const extras = state.composerPastePngBase64.slice();

    if (state.running) {
      if (
        tryEnqueueAgentRequest({
          workspacePath: state.workspacePath,
          modelId: state.modelId,
          prompt,
          providerId: state.agentProviderId,
          taskScreenshotPaths: [],
          extraScreenshotPngBase64: extras,
        })
      ) {
        promptEl.value = "";
        state.composerPastePngBase64 = [];
        setStatus(`Queued (${state.messageQueue.length} in queue).`, "neutral");
        render();
      }
      return;
    }

    await startAgentRequest({
      workspacePath: state.workspacePath,
      modelId: state.modelId,
      prompt,
      providerId: state.agentProviderId,
      sessionId: state.sessionId,
      taskScreenshotPaths: [],
      extraScreenshotPngBase64: extras,
    });
  }

  async function sendTaskById(taskId, workspacePath) {
    const ws = normalizePath(workspacePath || state.workspacePath);
    const task = tasksForWorkspace(ws).find((t) => String(t.id) === String(taskId));
    if (!task) {
      return;
    }
    state.workspacePath = ws;
    state.agentProviderId = normalizeProviderId(task.providerID);
    state.modelId = task.modelId || "auto";
    state.selectedTaskId = task.id;
    state.sidebarFocus = "agent";
    state.mainColumnMode = "agent";
    promptEl.value = task.content || "";
    addRecent(ws);
    await loadModels();
    await persistState();
    render();

    if (state.running) {
      if (
        tryEnqueueAgentRequest({
          workspacePath: ws,
          modelId: task.modelId || "auto",
          prompt: task.content || "",
          providerId: task.providerID,
          taskScreenshotPaths: task.screenshotPaths || [],
          extraScreenshotPngBase64: [],
        })
      ) {
        const preview = truncate(task.content || "", 48);
        setStatus(`Queued task${preview ? `: ${preview}` : ""} (${state.messageQueue.length} in queue).`, "neutral");
        render();
      }
      return;
    }

    await startAgentRequest({
      workspacePath: ws,
      modelId: task.modelId || "auto",
      prompt: task.content || "",
      providerId: task.providerID,
      sessionId: state.sessionId,
      taskScreenshotPaths: task.screenshotPaths || [],
      extraScreenshotPngBase64: [],
    });
  }

  async function stopRun() {
    if (!state.requestId) {
      return;
    }

    try {
      await fetch(`${bridgeUrl()}/api/tasks/${state.requestId}/stop`, {
        method: "POST",
      });
      state.messageQueue = [];
      setStatus("Stop requested — pending queued messages were cleared.");
    } catch {
      setStatus("Failed to stop the current run.", "error");
    }
  }

  promptEl.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") {
      return;
    }
    if (e.shiftKey) {
      return;
    }
    e.preventDefault();
    void sendPrompt();
  });

  function pushScreenshotFromDataUrl(dataUrl, bucket) {
    const raw = String(dataUrl || "");
    const base64 = raw.includes(",") ? raw.split(",")[1] : raw;
    if (!base64) {
      return false;
    }
    if (bucket.length >= MAX_SCREENSHOTS) {
      return false;
    }
    bucket.push(base64);
    return true;
  }

  /**
   * Clipboard image entries are not always exposed as `type: image/*` (e.g. macOS / Chrome may use
   * `kind: "file"` with an empty type while `getAsFile()` is still a valid image blob). Also check `files`.
   */
  function collectClipboardImageBlobs(clipboardData) {
    const out = [];
    const seen = new Set();
    const keyFor = (blob) => `${blob.size}:${blob.type || ""}:${blob.name || ""}`;

    function tryAdd(blob) {
      if (!blob || typeof blob.size !== "number" || blob.size <= 0) {
        return;
      }
      const mime = String(blob.type || "").toLowerCase();
      if (mime && !mime.startsWith("image/")) {
        return;
      }
      const k = keyFor(blob);
      if (seen.has(k)) {
        return;
      }
      seen.add(k);
      out.push(blob);
    }

    if (!clipboardData) {
      return out;
    }
    if (clipboardData.items) {
      for (let i = 0; i < clipboardData.items.length; i++) {
        const item = clipboardData.items[i];
        if (item.kind === "file") {
          try {
            tryAdd(item.getAsFile());
          } catch {
            /* ignore */
          }
        } else if (item.type && String(item.type).toLowerCase().startsWith("image/")) {
          try {
            tryAdd(item.getAsFile());
          } catch {
            /* ignore */
          }
        }
      }
    }
    if (clipboardData.files && clipboardData.files.length) {
      for (let i = 0; i < clipboardData.files.length; i++) {
        tryAdd(clipboardData.files[i]);
      }
    }
    return out;
  }

  function ingestImageBlobsIntoBucket(blobs, bucket, okMessage, errCapMessage) {
    if (!blobs.length) {
      return;
    }
    let pending = blobs.length;
    const doneOne = () => {
      pending -= 1;
      if (pending <= 0) {
        render();
      }
    };
    for (const blob of blobs) {
      const reader = new FileReader();
      reader.onload = () => {
        try {
          if (pushScreenshotFromDataUrl(reader.result, bucket)) {
            setStatus(typeof okMessage === "function" ? okMessage(bucket.length) : okMessage);
          } else {
            setStatus(errCapMessage, "error");
          }
        } finally {
          doneOne();
        }
      };
      reader.onerror = () => {
        doneOne();
      };
      reader.readAsDataURL(blob);
    }
  }

  function ingestClipboardImagesFromPaste(e, bucket, okMessage, errCapMessage) {
    const blobs = collectClipboardImageBlobs(e.clipboardData);
    if (!blobs.length) {
      return false;
    }
    e.preventDefault();
    e.stopPropagation();
    ingestImageBlobsIntoBucket(blobs, bucket, okMessage, errCapMessage);
    return true;
  }

  async function readImageBlobsFromNavigatorClipboard() {
    if (!navigator.clipboard || typeof navigator.clipboard.read !== "function") {
      return [];
    }
    const out = [];
    const seen = new Set();
    const keyFor = (blob) => `${blob.size}:${blob.type || ""}`;

    function tryAdd(blob) {
      if (!blob || typeof blob.size !== "number" || blob.size <= 0) {
        return;
      }
      const mime = String(blob.type || "").toLowerCase();
      if (mime && !mime.startsWith("image/")) {
        return;
      }
      const k = keyFor(blob);
      if (seen.has(k)) {
        return;
      }
      seen.add(k);
      out.push(blob);
    }

    const items = await navigator.clipboard.read();
    for (const item of items) {
      const types = item.types ? Array.from(item.types) : [];
      for (const type of types) {
        if (!String(type).toLowerCase().startsWith("image/")) {
          continue;
        }
        try {
          const blob = await item.getType(type);
          tryAdd(blob);
        } catch {
          /* ignore */
        }
      }
    }
    return out;
  }

  async function attachScreenshotsFromClipboardApi(bucket, okMessage, errCapMessage) {
    try {
      const blobs = await readImageBlobsFromNavigatorClipboard();
      if (!blobs.length) {
        setStatus("No image on the clipboard — copy a screenshot first.", "error");
        render();
        return;
      }
      ingestImageBlobsIntoBucket(blobs, bucket, okMessage, errCapMessage);
    } catch (err) {
      const name = err && err.name;
      const msg =
        name === "NotAllowedError"
          ? "Clipboard read blocked. Allow clipboard access for this site when prompted, or try again from a focused click."
          : err && err.message
            ? String(err.message)
            : "Could not read the clipboard.";
      setStatus(msg, "error");
      render();
    }
  }

  /** Capture phase: run before child handlers / default paste so image clips are not skipped or duplicated as text. */
  root.addEventListener(
    "paste",
    (e) => {
      const target = e.target;
      if (!target || !target.closest) {
        return;
      }
      if (target.closest('[data-role="prompt"]')) {
        ingestClipboardImagesFromPaste(
          e,
          state.composerPastePngBase64,
          (n) => `Composer: ${n} screenshot(s) attach on send.`,
          `At most ${MAX_SCREENSHOTS} composer screenshots.`,
        );
        return;
      }
      if (target.closest('[data-role="new-task-input"]')) {
        ingestClipboardImagesFromPaste(
          e,
          state.newTaskScreenshotsBase64,
          (n) => `New task: ${n} screenshot(s).`,
          `At most ${MAX_SCREENSHOTS} screenshots per task.`,
        );
      }
    },
    true,
  );

  panel.addEventListener("input", (e) => {
    const t = e.target;
    if (t && t.getAttribute && t.getAttribute("data-role") === "new-task-input") {
      state.newTaskDraft = t.value;
    }
    if (t && t.getAttribute && t.getAttribute("data-role") === "inline-edit") {
      state.editingTaskDraft = t.value;
    }
  });

  panel.addEventListener("click", (event) => {
    const target = event.target.closest("[data-action]");
    if (!target) {
      return;
    }

    const { action } = target.dataset;
    if (action === "close") {
      state.panelOpen = false;
      render();
      return;
    }
    if (action === "open-settings") {
      state.settingsOpen = true;
      render();
      return;
    }
    if (action === "close-settings") {
      state.settingsOpen = false;
      render();
      return;
    }
    if (action === "save-settings") {
      const v = bridgeUrlInput?.value?.trim() || DEFAULT_BRIDGE;
      state.bridgeBaseUrl = v.endsWith("/") ? v.slice(0, -1) : v;
      const prevProvider = state.agentProviderId;
      const nextProvider = normalizeProviderId(agentProviderSelect?.value);
      state.agentProviderId = nextProvider;
      if (nextProvider !== prevProvider) {
        state.sessionId = "";
        setStatus("Agent backend changed — started a new chat for correct session IDs.", "neutral");
      }
      state.settingsOpen = false;
      persistState();
      checkHealth();
      loadModels();
      loadProjects();
      void refreshTasksForVisibleProjects();
      render();
      return;
    }
    if (action === "pick-workspace") {
      pickWorkspace();
      return;
    }
    if (action === "create-hint") {
      setStatus("Use Cursor Metro on macOS to scaffold or clone with Preview. Import the folder here.");
      render();
      return;
    }
    if (action === "scroll-stream-top") {
      if (streamEl) {
        streamEl.scrollTop = 0;
      }
      return;
    }
    if (action === "paste-screenshot-composer") {
      void attachScreenshotsFromClipboardApi(
        state.composerPastePngBase64,
        (n) => `Composer: ${n} screenshot(s) attach on send.`,
        `At most ${MAX_SCREENSHOTS} composer screenshots.`,
      );
      return;
    }
    if (action === "paste-screenshot-new-task") {
      void attachScreenshotsFromClipboardApi(
        state.newTaskScreenshotsBase64,
        (n) => `New task: ${n} screenshot(s).`,
        `At most ${MAX_SCREENSHOTS} screenshots per task.`,
      );
      return;
    }
    if (action === "select-project") {
      const p = target.getAttribute("data-path");
      if (!p || state.running) {
        return;
      }
      state.workspacePath = p;
      state.activeProjectForTasks = p;
      state.sidebarFocus = "agent";
      state.mainColumnMode = "agent";
      state.selectedTaskId = null;
      addRecent(p);
      persistState();
      void refreshMetroTasks(p);
      render();
      return;
    }
    if (action === "show-tasks-page") {
      const p = target.getAttribute("data-path");
      if (!p || state.running) {
        return;
      }
      state.workspacePath = p;
      state.activeProjectForTasks = p;
      state.mainColumnMode = "tasks";
      state.sidebarFocus = "tasks";
      state.tasksListTab = "inProgress";
      addRecent(p);
      persistState();
      void refreshMetroTasks(p);
      render();
      return;
    }
    if (action === "select-task") {
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      const task = tasksForWorkspace(tws).find((t) => String(t.id) === String(id));
      if (!task || state.running) {
        return;
      }
      state.workspacePath = tws;
      state.activeProjectForTasks = tws;
      state.selectedTaskId = task.id;
      state.mainColumnMode = "agent";
      state.sidebarFocus = "agent";
      promptEl.value = task.content || "";
      addRecent(tws);
      persistState();
      render();
      return;
    }
    if (action === "sidebar-task-delete") {
      event.stopPropagation();
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      if (!id || !tws || state.running) {
        return;
      }
      void (async () => {
        try {
          await patchMetroTask(tws, id, { taskState: "deleted" });
          if (state.selectedTaskId === id) {
            state.selectedTaskId = null;
          }
          await refreshMetroTasks(tws);
          render();
        } catch (error) {
          setStatus(error.message || "Could not delete task.", "error");
          render();
        }
      })();
      return;
    }
    if (action === "toggle-task-composer") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        setStatus("Select a project first.", "error");
        render();
        return;
      }
      state.taskComposerOpen = !state.taskComposerOpen;
      if (state.taskComposerOpen) {
        state.newTaskModelId = state.modelId;
        state.newTaskTargetState = state.tasksListTab === "backlog" ? "backlog" : "inProgress";
      }
      render();
      return;
    }
    if (action === "tasks-tab") {
      const tab = target.getAttribute("data-tab");
      if (!tab || state.running) {
        return;
      }
      state.tasksListTab = tab;
      render();
      return;
    }
    if (action === "new-task-state") {
      const st = target.getAttribute("data-state");
      if (st === "backlog" || st === "inProgress") {
        state.newTaskTargetState = st;
      }
      render();
      return;
    }
    if (action === "remove-new-task-shot") {
      const idx = Number(target.getAttribute("data-index"));
      if (Number.isFinite(idx)) {
        state.newTaskScreenshotsBase64.splice(idx, 1);
      }
      render();
      return;
    }
    if (action === "cancel-new-task") {
      state.taskComposerOpen = false;
      state.newTaskDraft = "";
      state.newTaskScreenshotsBase64 = [];
      render();
      return;
    }
    if (action === "commit-new-task") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws || state.running) {
        return;
      }
      const draft = (newTaskInputEl && newTaskInputEl.value) || state.newTaskDraft || "";
      const trimmed = draft.trim();
      if (!trimmed && !state.newTaskScreenshotsBase64.length) {
        setStatus("Add a description or paste a screenshot.", "error");
        render();
        return;
      }
      void (async () => {
        try {
          const modelPick = newTaskModelEl && newTaskModelEl.value ? newTaskModelEl.value : state.newTaskModelId;
          await createMetroTaskOnBridge(ws, {
            content: trimmed || "Screenshot",
            taskState: state.newTaskTargetState,
            modelId: modelPick,
            providerId: state.agentProviderId,
            screenshotsPngBase64: state.newTaskScreenshotsBase64,
          });
          state.taskComposerOpen = false;
          state.newTaskDraft = "";
          state.newTaskScreenshotsBase64 = [];
          if (newTaskInputEl) {
            newTaskInputEl.value = "";
          }
          await refreshMetroTasks(ws);
          setStatus("Task saved to .metro/tasks.json (same as macOS).", "success");
          render();
        } catch (error) {
          setStatus(error.message || "Could not save task.", "error");
          render();
        }
      })();
      return;
    }
    if (action === "send-task") {
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      target.closest("details")?.removeAttribute("open");
      void sendTaskById(id, tws);
      return;
    }
    if (action === "edit-task") {
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      const task = tasksForWorkspace(tws).find((t) => String(t.id) === String(id));
      target.closest("details")?.removeAttribute("open");
      if (task) {
        state.editingTaskId = id;
        state.editingTaskDraft = task.content || "";
      }
      render();
      return;
    }
    if (action === "cancel-inline-task") {
      state.editingTaskId = null;
      state.editingTaskDraft = "";
      render();
      return;
    }
    if (action === "save-inline-task") {
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      const ta = panel.querySelector(`textarea[data-role="inline-edit"][data-task-id="${id}"]`);
      const next = ta && "value" in ta ? String(ta.value).trim() : state.editingTaskDraft.trim();
      if (!next) {
        setStatus("Task text cannot be empty.", "error");
        render();
        return;
      }
      void (async () => {
        try {
          await patchMetroTask(tws, id, { content: next });
          state.editingTaskId = null;
          state.editingTaskDraft = "";
          await refreshMetroTasks(tws);
          render();
        } catch (error) {
          setStatus(error.message || "Could not save.", "error");
          render();
        }
      })();
      return;
    }
    if (action === "patch-task-move") {
      const id = target.getAttribute("data-task-id");
      const tws = target.getAttribute("data-workspace");
      const to = target.getAttribute("data-to");
      target.closest("details")?.removeAttribute("open");
      if (!id || !tws || !to || state.running) {
        return;
      }
      void (async () => {
        try {
          await patchMetroTask(tws, id, { taskState: to });
          await refreshMetroTasks(tws);
          render();
        } catch (error) {
          setStatus(error.message || "Could not update task.", "error");
          render();
        }
      })();
      return;
    }
    if (action === "tasks-quick-commit") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        return;
      }
      state.workspacePath = ws;
      void runQuickTaskAndSend(ws, "Commit & push", QUICK_ACTION_COMMIT_PUSH);
      return;
    }
    if (action === "tasks-quick-fix") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        return;
      }
      state.workspacePath = ws;
      void runQuickTaskAndSend(ws, "Fix build", QUICK_ACTION_FIX_BUILD);
      return;
    }
    if (action === "refresh-models") {
      loadModels();
      return;
    }
    if (action === "quick-commit-push") {
      void runQuickAction(QUICK_ACTION_COMMIT_PUSH);
      return;
    }
    if (action === "quick-fix-build") {
      void runQuickAction(QUICK_ACTION_FIX_BUILD);
      return;
    }
    if (action === "send") {
      sendPrompt();
      return;
    }
    if (action === "stop") {
      stopRun();
      return;
    }
    if (action === "new-chat") {
      state.sessionId = "";
      state.selectedTaskId = null;
      state.messageQueue = [];
      persistState();
      setStatus("New chat: next send starts a fresh session.");
      render();
    }
  });

  modelEl.addEventListener("change", async () => {
    state.modelId = modelEl.value || "auto";
    await persistState();
  });

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type !== "metro-agent-toggle" && message.type !== "cursor-agent-toggle") {
      return;
    }

    state.visible = !state.visible;
    state.panelOpen = state.visible;
    render();
    if (state.visible) {
      checkHealth();
      loadModels();
      loadProjects();
      void refreshTasksForVisibleProjects();
    }
  });

  loadPersistedState().then(() => {
    render();
    checkHealth();
    loadModels();
    loadProjects();
    void refreshTasksForVisibleProjects();
  });
})();
