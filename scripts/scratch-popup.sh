#!/usr/bin/env bash
# Toggleable scratch terminal in a popup (prefix + t). A persistent detached
# session backs the popup, so its contents survive closing. Press the key
# again inside the popup (or detach) to close.
#   @cockpit-scratch-dir      — start directory (default: $HOME)
#   @cockpit-scratch-session  — backing session name (default: scratch)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

session="$(get_opt "@cockpit-scratch-session" "scratch")"
start_dir="$(get_opt "@cockpit-scratch-dir" "$HOME")"
start_dir="${start_dir/#\~/$HOME}"
width="$(get_opt "@cockpit-scratch-width" "80%")"
height="$(get_opt "@cockpit-scratch-height" "80%")"

if [ ! -d "$start_dir" ]; then
  cockpit_error "scratch directory does not exist: $start_dir"
  exit 1
fi
start_dir="$(cd "$start_dir" && pwd)" || exit 1

# Inside the scratch popup already? Toggle it closed.
if [ "$(current_session)" = "$session" ]; then
  exec tmux detach-client
fi

if ! session_exists "$session"; then
  tmux new-session -d -s "$session" -c "$start_dir"
fi

exec tmux display-popup -E -w "$width" -h "$height" \
  "env TMUX='' tmux attach-session -t '=$session'"
