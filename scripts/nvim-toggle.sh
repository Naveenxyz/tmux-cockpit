#!/usr/bin/env bash
# prefix+v — toggle a dedicated editor (nvim) window.
#   * From any other window: switch to this session's nvim window, creating it
#     (running `nvim .` at the project root) if there isn't one yet.
#   * From the nvim window: jump back to the previously active window.
#
# One nvim window per session — a window you always have — and "go back" rides
# on tmux's own last-window tracking.
#
# Options:
#   @cockpit-nvim-command  editor command to run (default: 'nvim .')
#   @cockpit-nvim-name     window name (default: 'nvim')

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "${TMUX:-}" ] || exit 0

command_str="$(get_opt "@cockpit-nvim-command" "nvim .")"
editor="${command_str%% *}"
require_cmd "$editor" "install it (or set @cockpit-nvim-command) for the editor toggle"

name="$(get_opt "@cockpit-nvim-name" "nvim")"

# Context of the window where the key was pressed.
sess="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
[ -n "$sess" ] || exit 0
win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
win_name="$(tmux display-message -p '#{window_name}' 2>/dev/null)"
marked="$(tmux show-options -w -t "$win" -qv "@cockpit-nvim-window" 2>/dev/null)"

# Already in the editor window -> go back to the previous window.
if [ "$marked" = "1" ] || [ "$win_name" = "$name" ]; then
  exec tmux last-window -t "$sess"
fi

# Otherwise switch to an existing editor window in this session, if any.
existing="$(tmux list-windows -t "$sess" \
  -F '#{window_id}'$'\t''#{@cockpit-nvim-window}'$'\t''#{window_name}' 2>/dev/null \
  | awk -F'\t' -v n="$name" '$2 == "1" || $3 == n { print $1; exit }')"
if [ -n "$existing" ]; then
  exec tmux select-window -t "$existing"
fi

# None yet: open one at the project root (fall back to the pane's directory).
root="$(session_root "$sess")"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  root="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)"
fi
[ -n "$root" ] && [ -d "$root" ] || root="$HOME"

new="$(tmux new-window -t "$sess:" -c "$root" -n "$name" \
  -P -F '#{window_id}' "$command_str" 2>/dev/null)"
[ -n "$new" ] || exit 0

# Tag the window and keep its name stable so the toggle keeps recognizing it.
tmux set-option -w -t "$new" "@cockpit-nvim-window" 1 2>/dev/null || true
tmux set-option -w -t "$new" automatic-rename off 2>/dev/null || true
