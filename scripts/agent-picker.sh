#!/usr/bin/env bash
# Agent picker — shown in a tmux popup. Lists AI-agent panes ordered by
# project, with a live (1s auto-refreshing) preview of the selected
# pane's screen.
#   prefix + a  all sessions          (agent-picker.sh)
#   prefix + A  current session only  (agent-picker.sh --current)
#
# Keys: enter/click jumps to the pane, 1-9 jump to the Nth entry,
# ctrl-r reloads the list, esc cancels.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd fzf "install it (brew install fzf) to use the agent picker"

scope=""
[ "$1" = "--current" ] && scope="--current"

list="$("$COCKPIT_SCRIPTS/agent-list.sh" $scope)"
if [ -z "$list" ]; then
  printf '\n  no agent panes found%s\n\n  (looking for: %s)\n' \
    "${scope:+ in this session}" \
    "$(get_opt "@cockpit-agents" "claude codex opencode pi")"
  sleep 1.4
  exit 0
fi

# Plain digit = jump to the Nth entry immediately.
digit_binds=()
for i in 1 2 3 4 5 6 7 8 9; do
  digit_binds+=(--bind "$i:pos($i)+accept")
done

# Extra space-separated fzf flags (e.g. a --color theme); see picker.sh.
extra_opts=()
fzf_opts="$(get_opt "@cockpit-fzf-opts" "")"
# Intentional word splitting into an array.
# shellcheck disable=SC2206
[ -n "$fzf_opts" ] && extra_opts=($fzf_opts)

selection="$(printf '%s\n' "$list" | fzf \
  "${extra_opts[@]}" \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='agent ❯ ' \
  --header='enter/1-9: jump to pane · ctrl-r: reload · esc: cancel' \
  --bind 'left-click:accept' \
  "${digit_binds[@]}" \
  --bind "ctrl-r:reload('$COCKPIT_SCRIPTS/agent-list.sh' $scope)" \
  --preview "'$COCKPIT_SCRIPTS/agent-preview.sh' {1}" \
  --preview-window 'right,60%,border-left')"

[ -n "$selection" ] || exit 0
exec "$COCKPIT_SCRIPTS/focus-agent-pane.sh" "${selection%%$'\t'*}"
