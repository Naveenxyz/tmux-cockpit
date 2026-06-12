#!/usr/bin/env bash
# Jump to an agent pane (A:<pane_id>): select its window and pane, then
# switch the client to its session.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

case "$1" in
  A:*) pane="${1#A:}" ;;
  *) exit 0 ;;
esac

session="$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)"
if [ -z "$session" ]; then
  cockpit_error "agent pane is gone"
  exit 1
fi

tmux select-window -t "$pane" 2>/dev/null
tmux select-pane -t "$pane" 2>/dev/null

if [ -n "$TMUX" ]; then
  exec tmux switch-client -t "=$session"
else
  exec tmux attach-session -t "=$session"
fi
