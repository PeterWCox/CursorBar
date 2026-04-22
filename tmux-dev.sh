#!/bin/bash

# Cursor Metro — tmux dev session (same toggle pattern as SideQuest tmux-dev.sh).
# - If session "CursorMetro" exists: kill it, then create a fresh session and attach.
# - From ~/.zshrc: tmetro() { "${CURSOR_METRO_ROOT:-$HOME/dev/CursorMetro}/tmux-dev.sh"; }

SESSION_NAME="CursorMetro"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
CHROME_DIR="${PROJECT_DIR}/Chrome"
PROJECT_DIR_Q=$(printf '%q' "$PROJECT_DIR")
CHROME_DIR_Q=$(printf '%q' "$CHROME_DIR")

if [[ ! -d "$CHROME_DIR" ]]; then
  echo "Expected Chrome directory at: $CHROME_DIR" >&2
  exit 1
fi

if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  echo "Killing existing session $SESSION_NAME..."
  tmux kill-session -t "$SESSION_NAME"
fi

echo "Creating new tmux session: $SESSION_NAME"
TMUX_CFG=()
[[ -f "$PROJECT_DIR/.tmux.conf" ]] && TMUX_CFG=(-f "$PROJECT_DIR/.tmux.conf")
tmux "${TMUX_CFG[@]}" new-session -d -s "$SESSION_NAME" -c "$CHROME_DIR"

# Bridge + extension watch (port cleanup then npm run dev — same as npm run tmetro)
tmux send-keys -t "$SESSION_NAME:0.0" "cd ${CHROME_DIR_Q} && npm run tmetro" C-m

tmux select-window -t "$SESSION_NAME:0"
tmux select-pane -t "$SESSION_NAME:0.0"

echo "Attaching to session $SESSION_NAME..."
tmux attach-session -t "$SESSION_NAME"
