(function bootstrap() {
  if (window.__iltmInjected) {
    return;
  }
  window.__iltmInjected = true;

  const DEFAULT_BRIDGE = "http://127.0.0.1:4317";
  /** Same asset as Cursor Metro `CursorMetroLogo` in `Assets.xcassets`, bundled under `extension/assets/`. */
  const CURSOR_METRO_LOGO_URL = chrome.runtime.getURL("assets/cursor-metro-logo.png");
  const storageKey = "iltmState";
  const tasksStorageKey = "iltmTasksV1";

  const QUICK_ACTION_COMMIT_PUSH = `Review the current git changes (e.g. git status and diff). Summarise them in a single, clear commit message and create one atomic commit, then push to the current branch. Only commit if the changes look intentional and ready to ship.`;

  const QUICK_ACTION_FIX_BUILD = `Fix the build. Identify and fix any compile errors, test failures, or other issues preventing the project from building successfully. Run the build (and tests if applicable) and iterate until everything passes.`;

  /** @type {{ streamParts: StreamPart[], sessionModelLabel: string | null, visible: boolean, panelOpen: boolean, running: boolean, requestId: string, sessionId: string, workspacePath: string, savedProjects: Array<{path:string,label:string}>, recentProjects: string[], modelId: string, models: Array<{id:string,label:string}>, statusText: string, statusTone: string, bridgeBaseUrl: string, tasks: MetroTask[], selectedTaskId: string | null, sidebarFocus: 'agent' | 'tasks', mainColumnMode: 'agent' | 'tasks', settingsOpen: boolean, activeProjectForTasks: string }} */
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
    statusText: "Click the extension icon to open Cursor Metro.",
    statusTone: "neutral",
    bridgeBaseUrl: DEFAULT_BRIDGE,
    /** @type {MetroTask[]} */
    tasks: [],
    selectedTaskId: null,
    sidebarFocus: "agent",
    mainColumnMode: "agent",
    settingsOpen: false,
    activeProjectForTasks: "",
  };

  /**
   * @typedef {{ id: string, workspacePath: string, title: string, agentPrompt: string, createdAt: number, completed?: boolean }} MetroTask
   * @typedef {{ type: 'thinking', text: string, completed: boolean } | { type: 'tool', callId: string, title: string, detail: string, status: string } | { type: 'assistant', text: string }} StreamPart
   */

  const root = document.createElement("div");
  root.id = "iltm-root";
  root.classList.add("iltm-hidden");

  const launcher = document.createElement("button");
  launcher.className = "iltm-launcher";
  launcher.type = "button";
  launcher.textContent = "+";
  launcher.title = "Open Cursor Metro";

  const panel = document.createElement("section");
  panel.className = "iltm-panel iltm-hidden";

  panel.innerHTML = `
    <div class="iltm-shell">
      <div class="iltm-main">
        <div class="iltm-main-header">
          <div class="iltm-main-title-block">
            <div class="iltm-title" data-role="main-title">Cursor Metro</div>
            <div class="iltm-subtle" data-role="main-subtitle">In-tab agent — streams like the macOS app.</div>
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
            <button type="button" class="iltm-button iltm-button--primary iltm-button--small" data-action="add-task-inline">Add task</button>
            <button type="button" class="iltm-pill" data-action="tasks-quick-commit">Commit &amp; push</button>
            <button type="button" class="iltm-pill" data-action="tasks-quick-fix">Fix build</button>
          </div>
          <div class="iltm-task-list" data-role="tasks-board"></div>
        </div>
      </div>

      <aside class="iltm-sidebar">
        <div class="iltm-sidebar-top">
          <div class="iltm-brand">
            <span class="iltm-brand-mark">Cursor Metro</span>
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
  const footerBranchEl = panel.querySelector('[data-role="footer-branch"]');
  const footerSpinnerEl = panel.querySelector('[data-role="footer-spinner"]');

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
    const stored = await chrome.storage.local.get([storageKey, tasksStorageKey]);
    const saved = stored[storageKey] || {};
    state.workspacePath = saved.workspacePath || "";
    state.recentProjects = Array.isArray(saved.recentProjects) ? saved.recentProjects : [];
    state.modelId = saved.modelId || "auto";
    state.sessionId = saved.sessionId || "";
    state.bridgeBaseUrl = typeof saved.bridgeBaseUrl === "string" && saved.bridgeBaseUrl.trim() ? saved.bridgeBaseUrl.trim() : DEFAULT_BRIDGE;
    const rawTasks = stored[tasksStorageKey];
    state.tasks = Array.isArray(rawTasks) ? rawTasks.filter((t) => t && t.id && t.workspacePath) : [];
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
      },
      [tasksStorageKey]: state.tasks,
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

  function tasksForWorkspace(ws) {
    const n = normalizePath(ws);
    return state.tasks.filter((t) => normalizePath(t.workspacePath) === n && !t.completed);
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
      const taskRows = tasksForWorkspace(path)
        .slice()
        .sort((a, b) => b.createdAt - a.createdAt)
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
            <div class="${cls.join(" ")}" data-action="select-task" data-task-id="${escapeHtml(t.id)}">
              <span class="iltm-sidebar-task-dot" style="background:hsl(${hue},70%,52%)"></span>
              <span class="iltm-sidebar-task-title">${escapeHtml(truncate(t.title, 42))}</span>
              <button type="button" class="iltm-sidebar-task-x" data-action="remove-task" data-task-id="${escapeHtml(t.id)}" title="Remove task">×</button>
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

  function renderTasksBoard() {
    if (!tasksBoardEl) {
      return;
    }
    const ws = state.activeProjectForTasks || state.workspacePath;
    if (!ws) {
      tasksBoardEl.innerHTML = `<div class="iltm-subtle">Select a project in the sidebar.</div>`;
      return;
    }
    const list = tasksForWorkspace(ws);
    if (!list.length) {
      tasksBoardEl.innerHTML = `<div class="iltm-tasks-empty">No tasks for <strong>${escapeHtml(basenamePath(ws))}</strong>. Add one or use quick actions.</div>`;
      return;
    }
    tasksBoardEl.innerHTML = list
      .slice()
      .sort((a, b) => b.createdAt - a.createdAt)
      .map((t) => {
        return `<div class="iltm-task-card">
          <div class="iltm-task-card-title">${escapeHtml(t.title)}</div>
          <div class="iltm-task-card-actions">
            <button type="button" class="iltm-button iltm-button--ghost iltm-button--small" data-action="send-task" data-task-id="${escapeHtml(t.id)}">Send to agent</button>
            <button type="button" class="iltm-button iltm-button--ghost iltm-button--small" data-action="complete-task" data-task-id="${escapeHtml(t.id)}">Done</button>
          </div>
        </div>`;
      })
      .join("");
  }

  function renderMainHeaders() {
    if (state.mainColumnMode === "tasks") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      mainTitleEl.textContent = "Tasks";
      mainSubtitleEl.textContent = ws ? basenamePath(ws) : "";
      return;
    }
    if (state.selectedTaskId) {
      const task = state.tasks.find((t) => t.id === state.selectedTaskId);
      if (task) {
        mainTitleEl.textContent = truncate(task.title, 72);
        mainSubtitleEl.textContent = projectLabel(task.workspacePath);
        return;
      }
    }
    mainTitleEl.textContent = "Cursor Metro";
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
    promptEl.disabled = state.running;
    modelEl.disabled = state.running;
    sendButton.disabled = state.running;
    stopButton.disabled = !state.running;

    for (const pill of panel.querySelectorAll(".iltm-pill")) {
      pill.disabled = state.running;
    }

    renderSidebar();
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
      render();
    } catch (error) {
      setStatus(error.message || "Could not pick folder.", "error");
      render();
    }
  }

  async function loadModels() {
    try {
      const response = await fetch(`${bridgeUrl()}/api/models`);
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to load models.");
      }

      state.models = data.models.length ? data.models : [{ id: "auto", label: "Auto" }];
      if (!state.models.some((model) => model.id === state.modelId)) {
        state.modelId = state.models[0].id;
      }
      await persistState();
      render();
    } catch (error) {
      state.models = [{ id: "auto", label: "Auto" }];
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
      await persistState();
      render();
      disconnectStream();
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

  async function runQuickAction(promptText) {
    if (state.running) {
      return;
    }
    promptEl.value = promptText;
    await sendPrompt();
  }

  function addTask(workspacePath, title, agentPrompt) {
    const ws = normalizePath(workspacePath);
    if (!ws) {
      return null;
    }
    const t = {
      id:
        typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
          ? crypto.randomUUID()
          : `t-${Date.now()}-${Math.random().toString(36).slice(2, 11)}`,
      workspacePath: ws,
      title: title.trim() || "Task",
      agentPrompt: (agentPrompt || title).trim(),
      createdAt: Date.now(),
    };
    state.tasks.push(t);
    persistState();
    render();
    return t.id;
  }

  async function sendPrompt() {
    state.modelId = modelEl.value || "auto";
    const prompt = promptEl.value.trim();

    if (!state.workspacePath.trim()) {
      setStatus("Select a project in the sidebar first.", "error");
      render();
      return;
    }
    if (!prompt) {
      setStatus("Enter a prompt first.", "error");
      render();
      return;
    }

    addRecent(state.workspacePath);

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
          workspacePath: state.workspacePath,
          modelId: state.modelId,
          prompt,
          sessionId: state.sessionId,
        }),
      });
      const data = await response.json();
      if (!response.ok || !data.ok) {
        throw new Error(data.error || "Failed to start task.");
      }

      state.requestId = data.requestId;
      attachStream(data.requestId);
      setStatus("Streaming…");
    } catch (error) {
      state.running = false;
      state.selectedTaskId = null;
      setStatus(error.message || "Failed to start task.", "error");
      render();
    }
  }

  async function sendTaskById(taskId) {
    const task = state.tasks.find((t) => t.id === taskId);
    if (!task || state.running) {
      return;
    }
    state.workspacePath = task.workspacePath;
    state.selectedTaskId = task.id;
    state.sidebarFocus = "agent";
    state.mainColumnMode = "agent";
    promptEl.value = task.agentPrompt;
    addRecent(state.workspacePath);
    await persistState();
    render();
    await sendPrompt();
  }

  async function stopRun() {
    if (!state.requestId) {
      return;
    }

    try {
      await fetch(`${bridgeUrl()}/api/tasks/${state.requestId}/stop`, {
        method: "POST",
      });
      setStatus("Stop requested.");
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
    if (!state.running) {
      sendPrompt();
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
      state.settingsOpen = false;
      persistState();
      checkHealth();
      loadModels();
      loadProjects();
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
      addRecent(p);
      persistState();
      render();
      return;
    }
    if (action === "select-task") {
      const id = target.getAttribute("data-task-id");
      const task = state.tasks.find((t) => t.id === id);
      if (!task || state.running) {
        return;
      }
      state.workspacePath = task.workspacePath;
      state.selectedTaskId = task.id;
      state.mainColumnMode = "agent";
      state.sidebarFocus = "agent";
      promptEl.value = task.agentPrompt;
      addRecent(task.workspacePath);
      persistState();
      render();
      return;
    }
    if (action === "remove-task") {
      event.stopPropagation();
      const id = target.getAttribute("data-task-id");
      state.tasks = state.tasks.filter((t) => t.id !== id);
      if (state.selectedTaskId === id) {
        state.selectedTaskId = null;
      }
      persistState();
      render();
      return;
    }
    if (action === "add-task-inline") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        setStatus("Select a project first.", "error");
        render();
        return;
      }
      const title = window.prompt("Task title (shown in sidebar):", "");
      if (title === null) {
        return;
      }
      const body = window.prompt("Prompt to send to the agent (defaults to title):", title);
      addTask(ws, title || "Task", body || title || "Task");
      return;
    }
    if (action === "send-task") {
      const id = target.getAttribute("data-task-id");
      void sendTaskById(id);
      return;
    }
    if (action === "complete-task") {
      const id = target.getAttribute("data-task-id");
      state.tasks = state.tasks.map((t) => (t.id === id ? { ...t, completed: true } : t));
      if (state.selectedTaskId === id) {
        state.selectedTaskId = null;
      }
      persistState();
      render();
      return;
    }
    if (action === "tasks-quick-commit") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        return;
      }
      state.workspacePath = ws;
      const id = addTask(ws, "Commit & push", QUICK_ACTION_COMMIT_PUSH);
      if (id) {
        void sendTaskById(id);
      }
      return;
    }
    if (action === "tasks-quick-fix") {
      const ws = state.activeProjectForTasks || state.workspacePath;
      if (!ws) {
        return;
      }
      state.workspacePath = ws;
      const id = addTask(ws, "Fix build", QUICK_ACTION_FIX_BUILD);
      if (id) {
        void sendTaskById(id);
      }
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
    if (message.type !== "cursor-agent-toggle") {
      return;
    }

    state.visible = !state.visible;
    state.panelOpen = state.visible;
    render();
    if (state.visible) {
      checkHealth();
      loadModels();
      loadProjects();
    }
  });

  loadPersistedState().then(() => {
    render();
    checkHealth();
    loadModels();
    loadProjects();
  });
})();
