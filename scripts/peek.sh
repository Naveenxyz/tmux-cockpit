#!/usr/bin/env bash
# Peek at a project from inside the picker (ctrl-p / alt-1..9): attach a
# nested tmux client to the project's session right here in the picker's
# terminal — detach (prefix + d) to drop back into the picker. Like the
# `zt` attach: if the directory has no session yet one is created (with the
# usual @cockpit-auto-commands layout) and reused on every later peek/open.
#
# Must be run via fzf's execute() (NOT execute-silent): the nested client
# needs the tty.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "$1" ] || exit 0
parse_target "$1"

if [ "$TARGET_KIND" = "session" ]; then
  session="$TARGET_VALUE"
  session_exists "$session" || exit 0
else
  path="$TARGET_VALUE"
  [ -n "$path" ] && [ -d "$path" ] || exit 0
  path="$(cd "$path" && pwd)"
  session="$(ensure_session_for_path "$path")"
  [ -n "$session" ] || exit 0
fi

# TMUX is cleared so tmux allows the nested attach inside the popup.
exec env TMUX='' tmux attach-session -t "=$session"
