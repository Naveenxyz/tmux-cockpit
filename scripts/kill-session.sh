#!/usr/bin/env bash
# Kill the session for a list entry (S:<session> or D:<path>), if one
# exists. Used by the ctrl-x binding inside the pickers.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "$1" ] || exit 0
parse_target "$1"

if [ "$TARGET_KIND" = "session" ]; then
  session="$TARGET_VALUE"
else
  session="$(find_session_for_path "$TARGET_VALUE")" || exit 0
fi

# Killing an attached session teleports its client mid-fzf; refuse rather
# than surprise. (Checking attachment beats comparing against "the current
# session", which is ambiguous outside a pane context.)
attached="$(tmux display-message -p -t "=$session" '#{?session_attached,1,0}' 2>/dev/null)"
if [ "$attached" = "1" ]; then
  cockpit_error "won't kill attached session $session — detach first"
  exit 0
fi

tmux kill-session -t "=$session" 2>/dev/null
