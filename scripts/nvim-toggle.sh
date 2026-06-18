#!/usr/bin/env bash
# prefix+v — toggle a dedicated editor (nvim) pane within the current window.
#   * From a normal pane: focus this window's nvim pane, creating it (running
#     `nvim .` at the project root) if there isn't one yet.
#   * From the nvim pane: jump back to the previously active pane.
#
# The toggle is per-window: the editor lives beside the work it belongs to,
# and tmux's own last-pane tracking is what "go back" rides on.
#
# Options:
#   @cockpit-nvim-command  editor command to run (default: 'nvim .')
#   @cockpit-nvim-split    'h' side-by-side (default) or 'v' stacked
#   @cockpit-nvim-size     size of the new pane (default: '50%')

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "${TMUX:-}" ] || exit 0

command_str="$(get_opt "@cockpit-nvim-command" "nvim .")"
editor="${command_str%% *}"
require_cmd "$editor" "install it (or set @cockpit-nvim-command) for the editor toggle"

# Context of the pane where the key was pressed.
pane="$(tmux display-message -p '#{pane_id}' 2>/dev/null)"
[ -n "$pane" ] || exit 0
win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
cur_cmd="$(tmux display-message -p '#{pane_current_command}' 2>/dev/null)"
marked="$(tmux show-options -p -t "$pane" -qv "@cockpit-nvim-pane" 2>/dev/null)"

is_editor() {
  [ "$1" = "1" ] && return 0
  case "$2" in nvim | vim | vi) return 0 ;; esac
  return 1
}

# Already in the editor pane -> go back to the previous pane.
if is_editor "$marked" "$cur_cmd"; then
  exec tmux last-pane -t "$win"
fi

# Otherwise focus an existing editor pane in this window, if any.
existing="$(tmux list-panes -t "$win" \
  -F '#{pane_id}'$'\t''#{@cockpit-nvim-pane}'$'\t''#{pane_current_command}' 2>/dev/null \
  | awk -F'\t' '$2 == "1" || $3 == "nvim" || $3 == "vim" || $3 == "vi" { print $1; exit }')"
if [ -n "$existing" ]; then
  exec tmux select-pane -t "$existing"
fi

# None yet: open one at the project root (fall back to the pane's directory).
sess="$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)"
root="$(session_root "$sess")"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  root="$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)"
fi
[ -n "$root" ] && [ -d "$root" ] || root="$HOME"

case "$(get_opt "@cockpit-nvim-split" "h")" in
  v | vertical) split_flag="-v" ;;
  *) split_flag="-h" ;;
esac
size="$(get_opt "@cockpit-nvim-size" "50%")"

new="$(tmux split-window "$split_flag" -l "$size" -c "$root" -t "$pane" \
  -P -F '#{pane_id}' "$command_str" 2>/dev/null)"
[ -n "$new" ] || exit 0

# Tag and title the pane so the toggle (and any picker) recognizes it.
tmux set-option -p -t "$new" "@cockpit-nvim-pane" 1 2>/dev/null || true
tmux select-pane -t "$new" -T nvim 2>/dev/null || true
