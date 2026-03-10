# Agent output: streaming and rendering

Short note on how the app gets agent output from Cursor and how it is streamed and rendered.

## Where the data comes from (Cursor “API”)

The app does **not** call a Cursor HTTP or WebSocket API directly. It uses the **Cursor CLI** — the `agent` binary (installed e.g. via `curl https://cursor.com/install -fsSL | bash`, typically at `~/.local/bin/agent`).

- **Create chat:** `agent create-chat` is run once per tab; stdout is the conversation ID. That ID is passed as `--resume <id>` for follow-up messages.
- **Stream a response:** The app runs the CLI with:
  - `-f` (non-interactive)
  - `-p "<prompt>"` and `--workspace <path>`
  - `--output-format stream-json` and `--stream-partial-output`

So “Cursor’s API” here is the **CLI’s stdout contract**: newline-delimited JSON events. The CLI itself talks to Cursor’s backend; the app only parses what the CLI prints.

## Stream format (CLI stdout)

Each line on stdout is one JSON object. The app decodes it as `StreamEvent` in `AgentRunner.swift` and maps it to `AgentStreamChunk`:

| Event `type` / `subtype` | Chunk / behaviour |
|--------------------------|-------------------|
| `thinking` / `delta`     | `AgentStreamChunk.thinkingDelta(text)` |
| `thinking` / `completed` | `AgentStreamChunk.thinkingCompleted` |
| `assistant` + `message.content[]` with `type: "text"` | `AgentStreamChunk.assistantText(text)` |
| Tool-call events (via `tool_call` and helpers) | `AgentStreamChunk.toolCall(AgentToolCallUpdate)` |
| `result`                 | Stream ends (no chunk; loop exits) |

Reading is done in a detached task: stdout is read in a loop, lines are split on `\n`, each line is decoded as `StreamEvent` and turned into one or more `AgentStreamChunk` values yielded on an `AsyncThrowingStream<AgentStreamChunk, Error>`.

## How streaming is consumed (UI layer)

In `PopoutView`, when the user sends a message:

1. A new `ConversationTurn` is appended (with `isStreaming: true`).
2. `AgentRunner.stream(...)` is called; it returns the `AsyncThrowingStream`.
3. A `Task` runs `for try await chunk in stream` and, for each chunk, updates the current tab’s turn and bumps `scrollToken`:
   - **thinkingDelta** → `appendThinkingText(text, to: turnID, in: tab)` (appends or extends the last thinking segment).
   - **thinkingCompleted** → `completeThinking(for: turnID, in: tab)` (clears `lastStreamPhase`).
   - **assistantText** → `mergeAssistantText(text, into: tab, turnID)` (appends or replaces the last assistant segment; handles prefix replacement when CLI sends a full prefix + delta).
   - **toolCall** → `mergeToolCall(update, into: tab, turnID)` (upserts a tool-call segment by `callID`).

After the stream ends (or on error/cancel), `finishStreaming(...)` is called: `isStreaming = false`, `streamTask = nil`, etc.

## State shape (conversation and segments)

- **AgentTab** holds `turns: [ConversationTurn]` and `scrollToken: UUID`.
- **ConversationTurn** has `segments: [ConversationSegment]`, `isStreaming`, and `lastStreamPhase` (thinking / assistant / toolCall).
- **ConversationSegment** is either:
  - **thinking** or **assistant**: `kind` + `text` (accumulated as chunks arrive).
  - **toolCall**: `kind` + `toolCall: ToolCallSegmentData` (callID, title, detail, status).

Streaming updates mutate the current turn’s `segments` in place; `scrollToken` is updated each time so the scroll view can auto-scroll to the bottom.

## How it’s rendered

- **OutputScrollView** wraps the content in a `ScrollView` and uses `scrollToken` to scroll to `"outputEnd"` when new content arrives.
- Content is built from `tab.turns`: each turn is a **ConversationTurnView**, which shows the user message and then a **VStack** of segments.
- **ConversationSegmentView** switches on `segment.kind`:
  - **thinking:** “Thinking” header + plain `Text(segment.text)` (monospaced).
  - **assistant:** `Text(assistantAttributedText(segment.text))` — the string is normalized (e.g. sentence breaks), then turned into an `AttributedString(markdown: ..., options: .init(interpretedSyntax: .full))` for inline markdown (bold, code, links, etc.).
  - **toolCall:** Card with icon, title, status (Running/Done/Failed), and optional detail (also markdown via `assistantAttributedText`).

So: **streaming** is “CLI stdout → AsyncThrowingStream → chunk handlers that mutate turn segments”; **rendering** is “SwiftUI views over those segments, with assistant and tool-call detail rendered as Markdown.”
