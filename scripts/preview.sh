#!/usr/bin/env bash
# fzf text preview for a list entry (S:<session> or D:<path>): session
# windows (if open), git status, and a directory listing.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "$1" ] || exit 0
parse_target "$1"

session=""
if [ "$TARGET_KIND" = "session" ]; then
  session="$TARGET_VALUE"
  path="$(session_path_of "$session")"
else
  path="$TARGET_VALUE"
  session="$(find_session_for_path "$path")" || session=""
fi

printf '\033[1m%s\033[0m\n' "$(display_path "$path")"

if [ -n "$session" ] && session_exists "$session"; then
  attached="$(tmux display-message -p -t "=$session" '#{?session_attached,attached,detached}' 2>/dev/null)"
  printf '\n\033[32m● session %s (%s)\033[0m\n' "$session" "$attached"
  tmux list-windows -t "=$session" -F '  #{window_index}: #{window_name}#{?window_active, *,}' 2>/dev/null
fi

[ -d "$path" ] || exit 0

if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '\n\033[33m%s\033[0m\n' "git: $(git -C "$path" branch --show-current 2>/dev/null)"
  git -C "$path" status -s 2>/dev/null | head -8
fi

echo
if command -v eza >/dev/null 2>&1; then
  eza --tree --level=2 --group-directories-first --color=always "$path" | head -40
elif command -v tree >/dev/null 2>&1; then
  tree -L 2 -C "$path" | head -40
else
  # ls is fine for a human-readable preview pane.
  # shellcheck disable=SC2012
  ls -la "$path" | head -40
fi
