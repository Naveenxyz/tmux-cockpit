#!/usr/bin/env bash
# One-shot project picker — shown in a tmux popup (prefix + o) or run
# directly from a terminal via bin/cockpit.
#
# Keys: enter/click opens, 1-9 jump straight to the Nth entry (digits are
# never typed into the query), ctrl-x kills a session, ctrl-d prunes a
# directory entry from zoxide. If the query is a real path (~/repo, ../repo, path/with/slash),
# Enter opens that path even if it is not in zoxide yet.

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
# Intentional word splitting into an array.
# shellcheck disable=SC2206
[ -n "$fzf_opts" ] && extra_opts=($fzf_opts)

result="$("$COCKPIT_SCRIPTS/project-list.sh" | fzf \
  "${extra_opts[@]}" \
  --ansi \
  --print-query \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='project ❯ ' \
  --header='enter/path: open · ctrl-x: kill session · ctrl-d: prune dir · esc: cancel' \
  --bind 'left-click:accept' \
  "${digit_binds[@]}" \
  --bind "ctrl-x:execute-silent('$COCKPIT_SCRIPTS/kill-session.sh' {1})+reload('$COCKPIT_SCRIPTS/project-list.sh')" \
  --bind "ctrl-d:execute-silent('$COCKPIT_SCRIPTS/prune-entry.sh' {1})+reload('$COCKPIT_SCRIPTS/project-list.sh')" \
  --preview "'$COCKPIT_SCRIPTS/preview.sh' {1}" \
  --preview-window 'right,55%,border-left')"

[ -n "$result" ] || exit 0

query="${result%%$'\n'*}"
if [ "$result" != "$query" ]; then
  selection="${result#*$'\n'}"
else
  selection=""
fi
selection="${selection%%$'\n'*}"

typed_dir="$(resolve_typed_dir "$query" 2>/dev/null || true)"

if [ -n "$typed_dir" ]; then
  exec "$COCKPIT_SCRIPTS/open-project.sh" "$typed_dir"
fi

[ -n "$selection" ] || exit 0
exec "$COCKPIT_SCRIPTS/open-project.sh" "${selection%%$'\t'*}"
