#!/usr/bin/env bash
# One-shot project picker — shown in a tmux popup (prefix + o) or run
# directly from a terminal via bin/cockpit.
#
# Keys: enter/click opens, 1-9 jump straight to the Nth entry (digits are
# never typed into the query), ctrl-x kills a session.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd fzf "install it (brew install fzf) to use the project picker"

# Plain digit = open the Nth entry immediately.
digit_binds=()
for i in 1 2 3 4 5 6 7 8 9; do
  digit_binds+=(--bind "$i:pos($i)+accept")
done

# Extra space-separated fzf flags (e.g. a --color theme). FZF_DEFAULT_OPTS
# doesn't reach the popup (tmux spawns it outside the user's shell), so
# this tmux option is the way to theme the picker.
extra_opts=()
fzf_opts="$(get_opt "@cockpit-fzf-opts" "")"
# shellcheck disable=SC2206 — intentional word splitting
[ -n "$fzf_opts" ] && extra_opts=($fzf_opts)

selection="$("$COCKPIT_SCRIPTS/project-list.sh" | fzf \
  "${extra_opts[@]}" \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='project ❯ ' \
  --header='enter/1-9: open · ctrl-x: kill session · esc: cancel' \
  --bind 'left-click:accept' \
  "${digit_binds[@]}" \
  --bind "ctrl-x:execute-silent('$COCKPIT_SCRIPTS/kill-session.sh' {1})+reload('$COCKPIT_SCRIPTS/project-list.sh')" \
  --preview "'$COCKPIT_SCRIPTS/preview.sh' {1}" \
  --preview-window 'right,55%,border-left')"

[ -n "$selection" ] || exit 0
exec "$COCKPIT_SCRIPTS/open-project.sh" "${selection%%$'\t'*}"
