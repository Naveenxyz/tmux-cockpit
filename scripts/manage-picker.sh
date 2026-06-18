#!/usr/bin/env bash
# Manage cockpit worktrees and features in one place — shown in a tmux popup
# (prefix + O) or run from a terminal via `cockpit -W`.
#
# Lists every worktree and feature under @cockpit-worktrees-dir.
#   enter / 1-9 / click  open the entry as a project session
#   ctrl-x               prune it (kills sessions, removes it correctly)
# Pruning runs in a full-screen step so it can confirm before destroying
# anything; the list reloads afterwards.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd fzf "install it (brew install fzf) to use the manage picker"

# Plain digit = open the Nth entry immediately.
digit_binds=()
for i in 1 2 3 4 5 6 7 8 9; do
  digit_binds+=(--bind "$i:pos($i)+accept")
done

extra_opts=()
fzf_opts="$(get_opt "@cockpit-fzf-opts" "")"
# Intentional word splitting into an array.
# shellcheck disable=SC2206
[ -n "$fzf_opts" ] && extra_opts=($fzf_opts)

selection="$("$COCKPIT_SCRIPTS/manage-list.sh" | fzf \
  "${extra_opts[@]}" \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='manage ❯ ' \
  --header=$'enter: open · ctrl-x: prune · esc: cancel\n◆ feature · ● worktree' \
  --bind 'left-click:accept' \
  "${digit_binds[@]}" \
  --bind "ctrl-x:execute('$COCKPIT_SCRIPTS/prune.sh' {1})+reload('$COCKPIT_SCRIPTS/manage-list.sh')" \
  --preview "'$COCKPIT_SCRIPTS/preview.sh' {1}" \
  --preview-window 'right,55%,border-left')"

[ -n "$selection" ] || exit 0

target="${selection%%$'\t'*}"
# Strip the W:/F: tag to a plain path for open-project.sh.
parse_target "$target"
exec "$COCKPIT_SCRIPTS/open-project.sh" "$TARGET_VALUE"
