const http = require("http");
const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const { randomUUID } = require("crypto");

const HOST = "127.0.0.1";
const PORT = Number(process.env.PORT || 4317);
const tasks = new Map();

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(JSON.stringify(payload, null, 2));
}

function sendSse(res, eventName, payload) {
  res.write(`event: ${eventName}\n`);
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error("Request body too large."));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function parseJsonBody(req) {
  return collectBody(req).then((body) => {
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
  return new Promise((resolve, reject) => {
    const child = spawn("agent", args, {
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

function appleReferenceTimestamp() {
  return (Date.now() - Date.UTC(2001, 0, 1, 0, 0, 0, 0)) / 1000;
}

function ensureMetroTask(workspacePath, prompt, modelId) {
  const metroDir = path.join(workspacePath, ".metro");
  const tasksPath = path.join(metroDir, "tasks.json");
  fs.mkdirSync(metroDir, { recursive: true });

  const existing = safeReadJson(tasksPath, { tasks: [] });
  const task = {
    id: randomUUID().toUpperCase(),
    content: prompt,
    createdAt: appleReferenceTimestamp(),
    taskState: "inProgress",
    completed: false,
    deleted: false,
    backlog: false,
    screenshotPaths: [],
    providerID: "cursor",
    modelId: modelId || "auto",
  };

  existing.tasks = Array.isArray(existing.tasks) ? existing.tasks : [];
  existing.tasks.unshift(task);
  fs.writeFileSync(tasksPath, `${JSON.stringify(existing, null, 2)}\n`, "utf8");
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

function startAgentRun(task) {
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

  const child = spawn("agent", args, {
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

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || `${HOST}:${PORT}`}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  try {
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, {
        ok: true,
        service: "cursor-agent-bridge",
        port: PORT,
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
      const stdout = await runAgentCommand(["models"]);
      sendJson(res, 200, {
        ok: true,
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

    if (req.method === "POST" && url.pathname === "/api/tasks") {
      const body = await parseJsonBody(req);
      const prompt = String(body.prompt || "").trim();
      const workspacePath = ensureWorkspace(body.workspacePath);
      const modelId = String(body.modelId || "auto").trim() || "auto";
      const sessionId = body.sessionId ? String(body.sessionId).trim() : "";

      if (!prompt) {
        throw new Error("Prompt is required.");
      }

      ensureMetroTask(workspacePath, prompt, modelId);
      const task = createTaskRecord({
        prompt,
        workspacePath,
        modelId,
        sessionId,
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
