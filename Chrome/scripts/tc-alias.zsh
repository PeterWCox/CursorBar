# Optional snippets for ~/.zshrc (not sourced from here — copy into your global zshrc).
#
# export CURSOR_METRO_ROOT="${CURSOR_METRO_ROOT:-$HOME/dev/CursorMetro}"
#
# tc() {
#   lsof -ti:4317 | xargs kill -9 2>/dev/null || true
#   (cd "${CURSOR_METRO_ROOT}/Chrome" && npm run dev)
# }
#
# Tmux dev for Metro (same idea as SideQuest `t` → repo tmux-dev.sh: existing "CursorMetro"
# session is killed, then a new one is created and attached):
#
# tmetro() {
#   "${CURSOR_METRO_ROOT:-$HOME/dev/CursorMetro}/tmux-dev.sh"
# }
