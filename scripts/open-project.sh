#!/usr/bin/env bash
# Open (or switch to) a project.
#   open-project.sh <path>          — session for a directory
#   open-project.sh S:<session>     — existing session by name
#   open-project.sh D:<path>        — directory (explicit form)
# Creates the session if needed: one window per @cockpit-auto-commands
# entry plus a plain-shell window, or a single plain window when the option
# is unset. Ends by exec-ing switch-client/attach, so callers must leave
# stdout/stderr on the terminal (attach needs the tty).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

parse_target "$1"

if [ "$TARGET_KIND" = "session" ]; then
  session="$TARGET_VALUE"
  if ! session_exists "$session"; then
    tmux display-message "tmux-cockpit: no such session: $session"
    exit 1
  fi
  root="$(session_path_of "$session")"
  [ -n "$root" ] && command -v zoxide >/dev/null 2>&1 && zoxide add "$root"
  if [ -n "$TMUX" ]; then
    exec tmux switch-client -t "=$session"
  else
    exec tmux attach-session -t "=$session"
  fi
fi

path="$TARGET_VALUE"
if [ -z "$path" ] || [ ! -d "$path" ]; then
  tmux display-message "tmux-cockpit: not a directory: $path"
  exit 1
fi
path="$(cd "$path" && pwd)"

# Keep zoxide's frecency fresh so the project ranks higher next time.
command -v zoxide >/dev/null 2>&1 && zoxide add "$path"

session="$(ensure_session_for_path "$path")"

if [ -n "$TMUX" ]; then
  exec tmux switch-client -t "=$session"
else
  exec tmux attach-session -t "=$session"
fi
