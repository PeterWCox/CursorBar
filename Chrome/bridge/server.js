const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const { randomUUID } = require("crypto");

const HOST = "127.0.0.1";
const PORT = Number(process.env.PORT || 4317);
const tasks = new Map();

/** Aligns with macOS `AgentProviderID` raw values (`ProjectTask` / `.metro/tasks.json`). */
const PROVIDER_CURSOR = "cursor";
const PROVIDER_CLAUDE_CODE = "claudeCode";

const CLAUDE_FALLBACK_MODELS = [
  { id: "auto", label: "Auto" },
  { id: "sonnet", label: "Sonnet" },
  { id: "sonnet[1m]", label: "Sonnet 1M" },
  { id: "opus", label: "Opus" },
  { id: "opus[1m]", label: "Opus 1M" },
  { id: "haiku", label: "Haiku" },
  { id: "best", label: "Best Available" },
  { id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6" },
  { id: "claude-opus-4-6", label: "Claude Opus 4.6" },
];

function normalizeProviderId(raw) {
  const s = String(raw || PROVIDER_CURSOR).trim();
  if (s === PROVIDER_CLAUDE_CODE || s.toLowerCase() === "claude" || s.toLowerCase() === "claudecode") {
    return PROVIDER_CLAUDE_CODE;
  }
  return PROVIDER_CURSOR;
}

function resolveBinary(name) {
  const home = process.env.HOME || "";
  const candidates = [
    path.join(home, ".local/bin", name),
    path.join("/usr/local/bin", name),
    path.join("/opt/homebrew/bin", name),
  ];
  for (const p of candidates) {
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch {
      /* continue */
    }
  }
  const pathEnv = process.env.PATH || "";
  for (const dir of pathEnv.split(":")) {
    if (!dir) {
      continue;
    }
    const p = path.join(dir, name);
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch {
      /* continue */
    }
  }
  return null;
}

function singleLine(text) {
  if (text == null) {
    return "";
  }
  return String(text).replace(/\s+/g, " ").trim();
}

function displayNameForClaudeTool(rawName) {
  if (!rawName || !String(rawName).trim()) {
    return "Tool";
  }
  const separated = String(rawName).replace(/([a-z0-9])([A-Z])/g, "$1 $2");
  return separated
    .split(/[\s_-]+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

function toolInputDetailFromPartialJSON(partial) {
  const trimmed = String(partial || "").trim();
  if (!trimmed) {
    return "";
  }
  try {
    const obj = JSON.parse(trimmed);
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      const keys = ["command", "description", "path", "file_path", "glob", "pattern", "query", "url", "prompt"];
      for (const k of keys) {
        if (obj[k] != null && String(obj[k]).trim()) {
          return String(obj[k]);
        }
      }
      return singleLine(JSON.stringify(obj));
    }
  } catch {
    /* incomplete JSON */
  }
  return singleLine(trimmed);
}

function claudeToolResultDetail(block, payload) {
  const parts = [];
  if (payload && payload.stdout && String(payload.stdout).trim() && !payload.no_output_expected) {
    parts.push(singleLine(payload.stdout));
  }
  if (payload && payload.stderr && String(payload.stderr).trim()) {
    parts.push(singleLine(payload.stderr));
  }
  if (payload && payload.interrupted) {
    parts.push("interrupted");
  }
  const contentStr =
    block && block.content != null
      ? typeof block.content === "string"
        ? block.content
        : singleLine(JSON.stringify(block.content))
      : "";
  if (contentStr && !parts.includes(contentStr)) {
    parts.push(contentStr);
  }
  return parts.filter(Boolean).join(" | ");
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(JSON.stringify(payload, null, 2));
}

function sendSse(res, eventName, payload) {
  res.write(`event: ${eventName}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function collectBody(req, maxBytes = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > maxBytes) {
        reject(new Error("Request body too large."));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function parseJsonBody(req, maxBytes = 1024 * 1024) {
  return collectBody(req, maxBytes).then((body) => {
    if (!body.trim()) {
      return {};
    }
    return JSON.parse(body);
  });
}

function stripAnsi(text) {
  return text.replace(/\u001b\[[0-9;]*[a-zA-Z]/g, "");
}

function normalizeModelOutput(stdout) {
  return stripAnsi(stdout)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => line.includes(" - "))
    .filter((line) => !line.startsWith("Available models"))
    .filter((line) => !line.startsWith("Loading"))
    .filter((line) => !line.startsWith("Tip:"))
    .map((line) => {
      const [rawId, ...rawLabelParts] = line.split(" - ");
      return {
        id: rawId.trim(),
        label: rawLabelParts.join(" - ").replace(/\s+\((?:default|current)\)\s*$/, "").trim(),
      };
    })
    .filter((model) => model.id && model.label);
}

function runAgentCommand(args, options = {}) {
  const agentPath = resolveBinary("agent");
  if (!agentPath) {
    return Promise.reject(new Error("Cursor Agent CLI (`agent`) not found on PATH."));
  }
  return new Promise((resolve, reject) => {
    const child = spawn(agentPath, args, {
      cwd: options.cwd || process.cwd(),
      env: {
        ...process.env,
        PATH: [path.join(process.env.HOME || "", ".local/bin"), process.env.PATH || ""]
          .filter(Boolean)
          .join(":"),
      },
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `agent exited with code ${code}`));
        return;
      }
      resolve(stdout);
    });
  });
}

function ensureWorkspace(workspacePath) {
  if (!workspacePath || typeof workspacePath !== "string") {
    throw new Error("A workspace path is required.");
  }

  const resolved = path.resolve(workspacePath);
  const stats = fs.statSync(resolved, { throwIfNoEntry: false });
  if (!stats || !stats.isDirectory()) {
    throw new Error(`Workspace does not exist: ${resolved}`);
  }
  return resolved;
}

function expandHome(p) {
  if (!p || typeof p !== "string") {
    return "";
  }
  const trimmed = p.trim();
  if (trimmed === "~") {
    return process.env.HOME || trimmed;
  }
  if (trimmed.startsWith("~/")) {
    return path.join(process.env.HOME || "", trimmed.slice(2));
  }
  return path.resolve(trimmed);
}

function loadProjectsConfig() {
  const configPath = path.join(__dirname, "projects.json");
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(configPath, "utf8"));
  } catch {
    return [];
  }
  const list = Array.isArray(raw.projects) ? raw.projects : [];
  const out = [];
  for (const entry of list) {
    const label = String(entry.label || "").trim();
    const rawPath = String(entry.path || "").trim();
    if (!label || !rawPath) {
      continue;
    }
    const expanded = expandHome(rawPath);
    if (!expanded) {
      continue;
    }
    const resolved = path.resolve(expanded);
    const stats = fs.statSync(resolved, { throwIfNoEntry: false });
    if (!stats || !stats.isDirectory()) {
      continue;
    }
    out.push({ label, path: resolved });
  }
  return out;
}

function pickFolderFromDialog() {
  return new Promise((resolve, reject) => {
    const platform = process.platform;
    if (platform === "darwin") {
      const child = spawn("osascript", [
        "-e",
        'POSIX path of (choose folder with prompt "Choose project folder")',
      ]);
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });
      child.on("error", reject);
      child.on("close", (code) => {
        if (code !== 0) {
          reject(new Error(stderr.trim() || "Folder selection was cancelled."));
          return;
        }
        const raw = stdout.trim();
        if (!raw) {
          reject(new Error("No folder selected."));
          return;
        }
        resolve(path.resolve(raw));
      });
      return;
    }

    if (platform === "linux") {
      const child = spawn("zenity", [
        "--file-selection",
        "--directory",
        "--title=Choose project folder",
      ]);
      let stdout = "";
      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.on("error", reject);
      child.on("close", (code) => {
        if (code !== 0) {
          reject(new Error("Folder selection was cancelled."));
          return;
        }
        const raw = stdout.trim();
        if (!raw) {
          reject(new Error("No folder selected."));
          return;
        }
        resolve(path.resolve(raw));
      });
      return;
    }

    reject(new Error("Native folder picker is only available on macOS or Linux (with zenity)."));
  });
}

function safeReadJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function appleReferenceTimestamp(dateMs = Date.now()) {
  return (dateMs - Date.UTC(2001, 0, 1, 0, 0, 0, 0)) / 1000;
}

const METRO_BODY_LIMIT = 28 * 1024 * 1024;

function tasksJsonPath(workspacePath) {
  return path.join(workspacePath, ".metro", "tasks.json");
}

function readMetroTasksDoc(workspacePath) {
  const doc = safeReadJson(tasksJsonPath(workspacePath), { tasks: [] });
  doc.tasks = Array.isArray(doc.tasks) ? doc.tasks : [];
  return doc;
}

function writeMetroTasksDoc(workspacePath, doc) {
  const p = tasksJsonPath(workspacePath);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, `${JSON.stringify(doc, null, 2)}\n`, "utf8");
}

function migratedTaskState(row) {
  if (row.taskState && typeof row.taskState === "string") {
    return row.taskState;
  }
  if (row.deleted) {
    return "deleted";
  }
  if (row.completed) {
    return "completed";
  }
  if (row.backlog) {
    return "backlog";
  }
  return "inProgress";
}

function syncDerivedTaskFlags(row) {
  const s = migratedTaskState(row);
  row.taskState = s;
  row.completed = s === "completed";
  row.deleted = s === "deleted";
  row.backlog = s === "backlog";
}

function setProjectTaskState(row, newState) {
  const prev = migratedTaskState(row);
  if (prev === newState) {
    syncDerivedTaskFlags(row);
    return;
  }

  switch (newState) {
    case "backlog":
    case "inProgress":
      row.taskState = newState;
      if (prev === "completed") {
        row.completedAt = null;
      }
      if (prev === "deleted") {
        row.deletedAt = null;
        row.preDeletionTaskState = null;
      }
      break;
    case "completed":
      row.taskState = "completed";
      if (prev !== "completed") {
        row.completedAt = appleReferenceTimestamp();
      }
      if (prev === "deleted") {
        row.deletedAt = null;
        row.preDeletionTaskState = null;
      }
      break;
    case "deleted":
      if (prev !== "deleted") {
        row.preDeletionTaskState = prev;
      }
      row.taskState = "deleted";
      row.deletedAt = appleReferenceTimestamp();
      break;
    default:
      break;
  }
  syncDerivedTaskFlags(row);
}

function metroAssetFullPath(workspacePath, relativeUnderMetro) {
  const rel = String(relativeUnderMetro || "").replace(/^\//, "");
  if (!rel || rel.includes("..")) {
    throw new Error("Invalid asset path.");
  }
  const metroRoot = path.resolve(workspacePath, ".metro");
  const full = path.resolve(workspacePath, ".metro", rel);
  if (!full.startsWith(metroRoot)) {
    throw new Error("Invalid asset path.");
  }
  return full;
}

function augmentPromptWithTaskScreenshots(workspacePath, prompt, relativePaths) {
  let out = String(prompt || "");
  const list = Array.isArray(relativePaths) ? relativePaths : [];
  for (const rel of list) {
    const abs = metroAssetFullPath(workspacePath, rel);
    if (fs.existsSync(abs)) {
      out += `\n\n[Screenshot attached: ${abs}]`;
    }
  }
  return out;
}

function appendComposerPasteScreenshots(workspacePath, prompt, pngBase64List) {
  let out = String(prompt || "");
  const list = Array.isArray(pngBase64List) ? pngBase64List : [];
  const metroDir = path.join(workspacePath, ".metro");
  fs.mkdirSync(metroDir, { recursive: true });
  for (const b64 of list) {
    const buf = Buffer.from(String(b64 || ""), "base64");
    if (!buf.length) {
      continue;
    }
    const name = `pasted-${randomUUID()}.png`;
    const rel = name;
    const full = path.join(metroDir, rel);
    fs.writeFileSync(full, buf);
    out += `\n\n[Screenshot attached: ${full}]`;
  }
  return out;
}

function persistTaskScreenshotBuffers(workspacePath, taskId, buffers) {
  const dir = path.join(workspacePath, ".metro", "screenshots");
  fs.mkdirSync(dir, { recursive: true });
  const paths = [];
  for (let i = 0; i < buffers.length; i++) {
    const rel = `screenshots/${taskId}_${i}.png`;
    fs.writeFileSync(path.join(workspacePath, ".metro", rel), buffers[i]);
    paths.push(rel);
  }
  return paths;
}

function removeScreenshotFiles(workspacePath, relativePaths) {
  for (const rel of relativePaths || []) {
    try {
      const full = metroAssetFullPath(workspacePath, rel);
      fs.unlinkSync(full);
    } catch {
      /* ignore */
    }
  }
}

function findMetroTaskIndex(doc, idStr) {
  const want = String(idStr || "").toLowerCase();
  return doc.tasks.findIndex((t) => String(t && t.id).toLowerCase() === want);
}

function makeNewMetroTaskRow(content, taskState, modelId, providerID, id) {
  const taskId = id || randomUUID();
  const now = appleReferenceTimestamp();
  const row = {
    id: taskId,
    content: String(content || "").trim(),
    createdAt: now,
    taskState: "inProgress",
    completed: false,
    completedAt: null,
    deleted: false,
    deletedAt: null,
    backlog: false,
    screenshotPaths: [],
    providerID: normalizeProviderId(providerID),
    modelId: String(modelId || "auto").trim() || "auto",
    preDeletionTaskState: null,
    agentTabID: null,
  };
  setProjectTaskState(row, taskState || "inProgress");
  return row;
}

function createTaskRecord(data) {
  const id = randomUUID();
  const task = {
    id,
    createdAt: Date.now(),
    listeners: new Set(),
    buffer: [],
    child: null,
    done: false,
    sessionId: data.sessionId || null,
    workspacePath: data.workspacePath,
    prompt: data.prompt,
    modelId: data.modelId || "auto",
    providerId: normalizeProviderId(data.providerId),
    lastAssistantMessage: "",
  };
  tasks.set(id, task);
  return task;
}

function publish(task, eventName, payload) {
  const message = { eventName, payload };
  task.buffer.push(message);
  for (const res of task.listeners) {
    sendSse(res, eventName, payload);
  }
}

function finishTask(task, payload = {}) {
  if (task.done) {
    return;
  }
  task.done = true;
  publish(task, "done", payload);
  for (const res of task.listeners) {
    res.end();
  }
  task.listeners.clear();
}

function summarizeToolCall(event) {
  if (!event.tool_call || typeof event.tool_call !== "object") {
    return null;
  }

  const [rawToolName, invocation] = Object.entries(event.tool_call)[0] || [];
  if (!rawToolName || !invocation) {
    return null;
  }

  const name = rawToolName.replace(/ToolCall$/, "");
  const title = name.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/^./, (char) => char.toUpperCase());
  const args = invocation.args || {};
  const baseDetail =
    args.command ||
    args.path ||
    args.globPattern ||
    args.pattern ||
    args.query ||
    args.url ||
    args.workingDirectory ||
    invocation.description ||
    "";

  let detail = baseDetail;
  let status = event.subtype || "started";
  const result = invocation.result || {};
  const failure = result.failure || result.error;

  if (failure) {
    status = "failed";
    detail = [baseDetail, failure.message || failure.stderr, failure.exitCode ? `exit ${failure.exitCode}` : ""]
      .filter(Boolean)
      .join(" | ");
  } else if (result.success) {
    status = result.success.exitCode && result.success.exitCode !== 0 ? "failed" : "completed";
    const duration =
      result.success.localExecutionTimeMs ||
      result.success.executionTime ||
      result.success.durationMs;
    detail = [baseDetail, duration ? `${duration}ms` : ""].filter(Boolean).join(" | ");
  }

  return {
    callId: event.call_id || randomUUID(),
    title,
    detail,
    status,
  };
}

function publishClaudeSession(task, sid) {
  if (!sid) {
    return;
  }
  task.sessionId = sid;
  publish(task, "session", {
    sessionId: task.sessionId,
    model: null,
    cwd: task.workspacePath,
    permissionMode: "bypassPermissions",
  });
}

function handleClaudeStreamEvent(task, event, activeToolUses) {
  if (!event || typeof event !== "object") {
    return;
  }

  switch (event.type) {
    case "content_block_start": {
      const idx = event.index;
      const block = event.content_block;
      if (idx == null || !block || block.type !== "tool_use") {
        return;
      }
      const callID = block.id || randomUUID();
      const title = displayNameForClaudeTool(block.name);
      activeToolUses.set(idx, {
        callID,
        title,
        partialInputJSON: "",
        resolvedDetail: "",
      });
      publish(task, "tool_call", {
        callId: callID,
        title,
        detail: "",
        status: "started",
      });
      break;
    }
    case "content_block_delta": {
      const delta = event.delta;
      const idx = event.index;
      if (!delta || typeof delta !== "object") {
        return;
      }
      if (delta.type === "text_delta" && delta.text) {
        task.lastAssistantMessage += delta.text;
        publish(task, "assistant_delta", { text: delta.text });
      } else if (delta.type === "thinking_delta" && delta.thinking) {
        publish(task, "thinking_delta", { text: delta.thinking });
      } else if (delta.type === "input_json_delta" && idx != null) {
        const state = activeToolUses.get(idx);
        if (!state) {
          return;
        }
        state.partialInputJSON += delta.partial_json || "";
        state.resolvedDetail = toolInputDetailFromPartialJSON(state.partialInputJSON);
        activeToolUses.set(idx, state);
        publish(task, "tool_call", {
          callId: state.callID,
          title: state.title,
          detail: state.resolvedDetail,
          status: "started",
        });
      }
      break;
    }
    case "content_block_stop": {
      const idx = event.index;
      if (idx != null && activeToolUses.has(idx)) {
        return;
      }
      publish(task, "thinking_completed", {});
      break;
    }
    default:
      break;
  }
}

function handleClaudeUserEnvelope(task, envelope, activeToolUses) {
  const content = envelope.message && envelope.message.content;
  if (!Array.isArray(content)) {
    return;
  }
  const payload = envelope.tool_use_result;

  for (const block of content) {
    if (!block || block.type !== "tool_result") {
      continue;
    }
    const callID = (block.tool_use_id || "").trim();
    if (!callID) {
      continue;
    }

    let state = null;
    let stateIndex = null;
    for (const [index, s] of activeToolUses.entries()) {
      if (s.callID === callID) {
        state = s;
        stateIndex = index;
        break;
      }
    }
    if (stateIndex != null) {
      activeToolUses.delete(stateIndex);
    }

    const baseDetail = state && state.resolvedDetail ? state.resolvedDetail : "";
    const resultDetail = claudeToolResultDetail(block, payload);
    const detail = [baseDetail, resultDetail].filter(Boolean).join(" | ");

    publish(task, "tool_call", {
      callId: callID,
      title: (state && state.title) || "Tool",
      detail,
      status: block.is_error ? "failed" : "completed",
    });
  }
}

function processClaudeJsonLine(task, line, activeToolUses) {
  let envelope;
  try {
    envelope = JSON.parse(line);
  } catch {
    return;
  }

  if (envelope.session_id) {
    publishClaudeSession(task, envelope.session_id);
  }

  const t = envelope.type;
  if (t === "stream_event") {
    handleClaudeStreamEvent(task, envelope.event, activeToolUses);
  } else if (t === "user") {
    handleClaudeUserEnvelope(task, envelope, activeToolUses);
  }
}

function startClaudeCodeRun(task) {
  const claudePath = resolveBinary("claude");
  if (!claudePath) {
    publish(task, "run_error", {
      message: "Claude Code CLI (`claude`) not found on PATH.",
    });
    finishTask(task, { ok: false });
    return;
  }

  const args = [
    "-p",
    task.prompt,
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--permission-mode",
    "bypassPermissions",
  ];

  if (task.sessionId) {
    args.push("--resume", task.sessionId);
  }

  if (task.modelId && task.modelId !== "auto") {
    args.push("--model", task.modelId);
  }

  const child = spawn(claudePath, args, {
    cwd: task.workspacePath,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      PATH: [path.join(process.env.HOME || "", ".local/bin"), process.env.PATH || ""]
        .filter(Boolean)
        .join(":"),
    },
  });

  task.child = child;
  let stdoutBuffer = "";
  let stderrBuffer = "";
  const activeToolUses = new Map();

  publish(task, "status", {
    state: "started",
    requestId: task.id,
    workspacePath: task.workspacePath,
    modelId: task.modelId,
    providerId: PROVIDER_CLAUDE_CODE,
  });

  child.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk.toString();
    while (stdoutBuffer.includes("\n")) {
      const newlineIndex = stdoutBuffer.indexOf("\n");
      const line = stdoutBuffer.slice(0, newlineIndex).trim();
      stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1);
      if (!line) {
        continue;
      }
      processClaudeJsonLine(task, line, activeToolUses);
    }
  });

  child.stderr.on("data", (chunk) => {
    stderrBuffer += chunk.toString();
  });

  child.on("error", (error) => {
    publish(task, "run_error", { message: error.message });
    finishTask(task, { ok: false });
  });

  child.on("close", (code) => {
    if (code !== 0) {
      publish(task, "run_error", {
        message: stderrBuffer.trim() || `claude exited with code ${code}`,
        exitCode: code,
      });
      finishTask(task, { ok: false, exitCode: code });
      return;
    }

    publish(task, "result", {
      isError: false,
      result: task.lastAssistantMessage,
      durationMs: null,
      sessionId: task.sessionId,
      requestId: task.id,
    });

    finishTask(task, {
      ok: true,
      sessionId: task.sessionId,
      assistantText: task.lastAssistantMessage,
    });
  });
}

function startCursorAgentRun(task) {
  const agentPath = resolveBinary("agent");
  if (!agentPath) {
    publish(task, "run_error", {
      message: "Cursor Agent CLI (`agent`) not found on PATH.",
    });
    finishTask(task, { ok: false });
    return;
  }

  const args = [
    "-f",
    "-p",
    task.prompt,
    "--trust",
    "--workspace",
    task.workspacePath,
    "--output-format",
    "stream-json",
    "--stream-partial-output",
  ];

  if (task.sessionId) {
    args.push("--resume", task.sessionId);
  }

  if (task.modelId && task.modelId !== "auto") {
    args.push("--model", task.modelId);
  }

  const child = spawn(agentPath, args, {
    cwd: task.workspacePath,
    env: {
      ...process.env,
      PATH: [path.join(process.env.HOME || "", ".local/bin"), process.env.PATH || ""]
        .filter(Boolean)
        .join(":"),
    },
  });

  task.child = child;
  let stdoutBuffer = "";
  let stderrBuffer = "";

  publish(task, "status", {
    state: "started",
    requestId: task.id,
    workspacePath: task.workspacePath,
    modelId: task.modelId,
    providerId: PROVIDER_CURSOR,
  });

  child.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk.toString();

    while (stdoutBuffer.includes("\n")) {
      const newlineIndex = stdoutBuffer.indexOf("\n");
      const line = stdoutBuffer.slice(0, newlineIndex).trim();
      stdoutBuffer = stdoutBuffer.slice(newlineIndex + 1);

      if (!line) {
        continue;
      }

      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }

      if (event.type === "system" && event.subtype === "init") {
        task.sessionId = event.session_id || task.sessionId;
        publish(task, "session", {
          sessionId: task.sessionId,
          model: event.model,
          cwd: event.cwd,
          permissionMode: event.permissionMode,
        });
        continue;
      }

      if (event.type === "thinking") {
        if (event.subtype === "delta" && event.text) {
          publish(task, "thinking_delta", { text: event.text });
        } else if (event.subtype === "completed") {
          publish(task, "thinking_completed", {});
        }
        continue;
      }

      if (event.type === "tool_call") {
        const toolCall = summarizeToolCall(event);
        if (toolCall) {
          publish(task, "tool_call", toolCall);
        }
        continue;
      }

      if (event.type === "assistant" && event.message && Array.isArray(event.message.content)) {
        const text = event.message.content
          .filter((item) => item.type === "text" && item.text)
          .map((item) => item.text)
          .join("");

        // Match Cursor Metro / CursorAgentProvider: each line is a stream-json chunk; with
        // --stream-partial-output, text is an incremental delta — always forward it.
        if (text) {
          task.lastAssistantMessage += text;
          publish(task, "assistant_delta", { text });
        }
        continue;
      }

      if (event.type === "result") {
        publish(task, "result", {
          isError: Boolean(event.is_error),
          result: event.result || task.lastAssistantMessage,
          durationMs: event.duration_ms || null,
          sessionId: event.session_id || task.sessionId,
          requestId: event.request_id || null,
        });
      }
    }
  });

  child.stderr.on("data", (chunk) => {
    stderrBuffer += chunk.toString();
  });

  child.on("error", (error) => {
    publish(task, "run_error", { message: error.message });
    finishTask(task, { ok: false });
  });

  child.on("close", (code) => {
    if (code !== 0) {
      publish(task, "run_error", {
        message: stderrBuffer.trim() || `agent exited with code ${code}`,
        exitCode: code,
      });
      finishTask(task, { ok: false, exitCode: code });
      return;
    }

    finishTask(task, {
      ok: true,
      sessionId: task.sessionId,
      assistantText: task.lastAssistantMessage,
    });
  });
}

function startAgentRun(task) {
  if (task.providerId === PROVIDER_CLAUDE_CODE) {
    startClaudeCodeRun(task);
  } else {
    startCursorAgentRun(task);
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || `${HOST}:${PORT}`}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,PATCH,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  try {
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, {
        ok: true,
        service: "cursor-metro-chrome-bridge",
        port: PORT,
        providers: [PROVIDER_CURSOR, PROVIDER_CLAUDE_CODE],
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/projects") {
      sendJson(res, 200, {
        ok: true,
        projects: loadProjectsConfig(),
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/models") {
      const providerId = normalizeProviderId(url.searchParams.get("provider"));
      if (providerId === PROVIDER_CLAUDE_CODE) {
        sendJson(res, 200, {
          ok: true,
          providerId: PROVIDER_CLAUDE_CODE,
          models: CLAUDE_FALLBACK_MODELS,
        });
        return;
      }

      const stdout = await runAgentCommand(["models"]);
      sendJson(res, 200, {
        ok: true,
        providerId: PROVIDER_CURSOR,
        models: normalizeModelOutput(stdout),
      });
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/pick-folder") {
      const picked = await pickFolderFromDialog();
      sendJson(res, 200, {
        ok: true,
        path: picked,
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/metro-tasks") {
      const workspacePath = ensureWorkspace(url.searchParams.get("workspacePath"));
      const doc = readMetroTasksDoc(workspacePath);
      for (const row of doc.tasks) {
        syncDerivedTaskFlags(row);
      }
      sendJson(res, 200, {
        ok: true,
        workspacePath,
        tasks: doc.tasks,
      });
      return;
    }

    if (req.method === "GET" && url.pathname === "/api/metro-asset") {
      const workspacePath = ensureWorkspace(url.searchParams.get("workspacePath"));
      const rel = url.searchParams.get("path");
      const full = metroAssetFullPath(workspacePath, rel);
      const st = fs.statSync(full, { throwIfNoEntry: false });
      if (!st || !st.isFile()) {
        sendJson(res, 404, { ok: false, error: "Not found." });
        return;
      }
      const data = fs.readFileSync(full);
      res.writeHead(200, {
        "Content-Type": "image/png",
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "*",
      });
      res.end(data);
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/metro-tasks") {
      const body = await parseJsonBody(req, METRO_BODY_LIMIT);
      const workspacePath = ensureWorkspace(body.workspacePath);
      const contentRaw = String(body.content ?? "").trim();
      const taskState = String(body.taskState || "inProgress").trim() || "inProgress";
      const modelId = String(body.modelId || "auto").trim() || "auto";
      const providerID = normalizeProviderId(body.providerId);
      const pngList = Array.isArray(body.screenshotsPngBase64) ? body.screenshotsPngBase64 : [];

      if (!contentRaw && !pngList.length) {
        throw new Error("Task content or at least one screenshot is required.");
      }

      const content = contentRaw || "Screenshot";
      const row = makeNewMetroTaskRow(content, taskState, modelId, providerID);
      const buffers = pngList.map((b) => Buffer.from(String(b), "base64")).filter((b) => b.length);
      row.screenshotPaths = persistTaskScreenshotBuffers(workspacePath, row.id, buffers);

      const doc = readMetroTasksDoc(workspacePath);
      doc.tasks.unshift(row);
      writeMetroTasksDoc(workspacePath, doc);

      sendJson(res, 200, { ok: true, task: row });
      return;
    }

    if (req.method === "PATCH" && url.pathname === "/api/metro-tasks") {
      const body = await parseJsonBody(req, METRO_BODY_LIMIT);
      const workspacePath = ensureWorkspace(body.workspacePath);
      const id = String(body.id || "").trim();
      if (!id) {
        throw new Error("Task id is required.");
      }

      const doc = readMetroTasksDoc(workspacePath);
      const idx = findMetroTaskIndex(doc, id);
      if (idx < 0) {
        sendJson(res, 404, { ok: false, error: "Task not found." });
        return;
      }

      const row = doc.tasks[idx];
      syncDerivedTaskFlags(row);

      if (body.content != null) {
        row.content = String(body.content).trim();
      }
      if (body.taskState != null) {
        setProjectTaskState(row, String(body.taskState).trim());
      }
      if (body.modelId != null) {
        row.modelId = String(body.modelId).trim() || "auto";
      }
      if (body.providerId != null) {
        row.providerID = normalizeProviderId(body.providerId);
      }

      if (Array.isArray(body.screenshotsPngBase64)) {
        const oldPaths = Array.isArray(row.screenshotPaths) ? [...row.screenshotPaths] : [];
        const buffers = body.screenshotsPngBase64.map((b) => Buffer.from(String(b), "base64")).filter((b) => b.length);
        const newPaths = persistTaskScreenshotBuffers(workspacePath, row.id, buffers);
        const toRemove = oldPaths.filter((p) => !newPaths.includes(p));
        removeScreenshotFiles(workspacePath, toRemove);
        row.screenshotPaths = newPaths;
      }

      syncDerivedTaskFlags(row);
      writeMetroTasksDoc(workspacePath, doc);
      sendJson(res, 200, { ok: true, task: row });
      return;
    }

    if (req.method === "POST" && url.pathname === "/api/tasks") {
      const body = await parseJsonBody(req, METRO_BODY_LIMIT);
      const prompt = String(body.prompt || "").trim();
      const workspacePath = ensureWorkspace(body.workspacePath);
      const modelId = String(body.modelId || "auto").trim() || "auto";
      const sessionId = body.sessionId ? String(body.sessionId).trim() : "";
      const providerId = normalizeProviderId(body.providerId);

      let finalPrompt = augmentPromptWithTaskScreenshots(workspacePath, prompt, body.taskScreenshotPaths);
      finalPrompt = appendComposerPasteScreenshots(workspacePath, finalPrompt, body.extraScreenshotPngBase64);

      if (!finalPrompt.trim()) {
        throw new Error("Prompt is required.");
      }

      const task = createTaskRecord({
        prompt: finalPrompt,
        workspacePath,
        modelId,
        sessionId,
        providerId,
      });
      startAgentRun(task);

      sendJson(res, 200, {
        ok: true,
        requestId: task.id,
      });
      return;
    }

    if (req.method === "GET" && url.pathname.startsWith("/api/stream/")) {
      const requestId = url.pathname.split("/").pop();
      const task = requestId ? tasks.get(requestId) : null;

      if (!task) {
        sendJson(res, 404, { ok: false, error: "Request not found." });
        return;
      }

      res.writeHead(200, {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "Access-Control-Allow-Origin": "*",
      });
      res.write("\n");

      task.listeners.add(res);
      for (const entry of task.buffer) {
        sendSse(res, entry.eventName, entry.payload);
      }

      req.on("close", () => {
        task.listeners.delete(res);
      });

      if (task.done) {
        res.end();
      }
      return;
    }

    if (req.method === "POST" && url.pathname.startsWith("/api/tasks/") && url.pathname.endsWith("/stop")) {
      const [, , , requestId] = url.pathname.split("/");
      const task = tasks.get(requestId);
      if (!task) {
        sendJson(res, 404, { ok: false, error: "Request not found." });
        return;
      }

      if (task.child && !task.done) {
        task.child.kill("SIGTERM");
      }

      sendJson(res, 200, { ok: true });
      return;
    }

    sendJson(res, 404, { ok: false, error: "Not found." });
  } catch (error) {
    sendJson(res, 400, {
      ok: false,
      error: error instanceof Error ? error.message : "Unknown error",
    });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Cursor Agent bridge listening on http://${HOST}:${PORT}`);
});
