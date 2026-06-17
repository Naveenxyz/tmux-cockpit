#!/usr/bin/env bash
# Multi-repo "feature" creator. Invoked from the project picker (ctrl-f).
# Flow:
#   1. name the feature (passed in from the picker query, or prompted here)
#   2. multi-select git repos (TAB to mark several, ctrl-a for all)
#   3. hand off to open-feature.sh, which clones (or worktrees) each repo
#      under the feature folder, copies in .env files, and opens a session.
# An existing feature of the same name is recreated by open-feature.sh.
#
#   feature-picker.sh [initial-name]

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd git "install git to use feature worktrees"
require_cmd fzf "install it (brew install fzf) to use the feature picker"

# Show a message in the popup long enough to read, then exit non-zero.
fail_popup() {
  clear
  printf '\033[31mtmux-cockpit:\033[0m %s\n' "$*"
  sleep 1.8
  exit 1
}

choose_name() {
  local result query
  # Empty candidate list + --print-query: fzf exits non-zero with no match,
  # but still prints whatever the user typed — that is the feature name.
  result="$(fzf \
    --print-query \
    --layout=reverse \
    --prompt='feature name ❯ ' \
    --header='name the multi-repo feature, then enter · esc: cancel' \
    --preview "printf 'feature folder:\n\n%s/{q}\n' '$(display_path "$(features_base)")'" \
    --preview-window 'right,55%,border-left' </dev/null)" || true
  query="${result%%$'\n'*}"
  trim_ws "$query"
}

name="$(trim_ws "${1:-}")"
[ -n "$name" ] || name="$(choose_name)"
[ -n "$name" ] || exit 0

# A feature name is a single folder/branch component — no path separators.
case "$name" in
  */* | . | ..) fail_popup "invalid feature name: $name" ;;
esac

feature_dir="$(features_base)/$name"
mode="$(feature_mode)"

# Multi-select is the whole point here, so make it loud: tab marks a repo,
# ctrl-a marks all. A plain enter still works for a single highlighted repo.
# Two header lines so the keys never get truncated in a narrow popup.
hdr="feature '$name' ($mode)"
[ -e "$feature_dir" ] && hdr="$hdr · EXISTS → will be recreated"
hdr="$hdr"$'\nTAB: mark repo · ctrl-a: all · enter: create · esc: cancel'

selection="$("$COCKPIT_SCRIPTS/repo-list.sh" | fzf \
  --ansi \
  --multi \
  --info=inline \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='repos (mark with TAB) ❯ ' \
  --marker='✓ ' \
  --pointer='▶' \
  --bind 'ctrl-a:toggle-all' \
  --header="$hdr" \
  --preview "'$COCKPIT_SCRIPTS/preview.sh' {1}" \
  --preview-window 'right,55%,border-left')"

[ -n "$selection" ] || exit 0

repos=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  repos+=("${line%%$'\t'*}")
done <<< "$selection"

[ "${#repos[@]}" -gt 0 ] || exit 0

clear
printf 'Creating feature (%s)\n\n  feature: %s\n  folder:  %s\n  repos:   %d\n' \
  "$mode" "$name" "$(display_path "$feature_dir")" "${#repos[@]}"
if [ -e "$feature_dir" ]; then
  printf '\n  \033[33m! recreating: the existing folder and its sessions will be removed\033[0m\n'
fi
printf '\n'

exec "$COCKPIT_SCRIPTS/open-feature.sh" "$name" "${repos[@]}"
