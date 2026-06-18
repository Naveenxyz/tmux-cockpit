#!/usr/bin/env bash
# Emit cockpit-managed worktrees and features under @cockpit-worktrees-dir,
# one entry per line:
#   F:<path>\t<display text>   a multi-repo feature folder
#   W:<path>\t<display text>   a single git worktree (a repo-group child)
#
# Layout produced by the rest of cockpit (see worktree.sh):
#   <worktrees>/features/<name>/<repo>...      -> features
#   <worktrees>/<repo-slug>/.cockpit-repo      -> repo-group marker
#   <worktrees>/<repo-slug>/<branch>           -> worktrees
#
# Custom-path worktrees created with `-w --path` outside the worktrees dir
# are not centrally tracked and so are not listed here.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

base="$(worktrees_base)"
base="${base%/}"
features="$(features_base)"
[ -d "$base" ] || exit 0

# Mark with " (open)" when a cockpit session is rooted at this path.
open_marker() {
  local path="$1"
  if [ -n "$(sessions_under "$path" | head -1)" ]; then
    printf ' \033[2m(open)\033[0m'
  fi
}

# Features first, then loose worktrees grouped by repo.
if [ -d "$features" ]; then
  for fdir in "$features"/*/; do
    fdir="${fdir%/}"
    [ -d "$fdir" ] || continue
    name="${fdir##*/}"

    # Count repo subdirs and detect the mode from a sample child (.git file =
    # worktree mode, .git dir = clone mode).
    nrepos=0
    mode="empty"
    for repo in "$fdir"/*/; do
      repo="${repo%/}"
      [ -d "$repo" ] || continue
      nrepos=$((nrepos + 1))
      if [ "$nrepos" -eq 1 ]; then
        if [ -f "$repo/.git" ]; then mode="worktree"; else mode="clone"; fi
      fi
    done

    printf 'F:%s\t\033[2mfeat\033[0m \033[35m◆\033[0m %-26s \033[2m%d repo(s) · %s · %s\033[0m%s\n' \
      "$fdir" "$name" "$nrepos" "$mode" "$(display_path "$fdir")" "$(open_marker "$fdir")"
  done
fi

for group in "$base"/*/; do
  group="${group%/}"
  [ -d "$group" ] || continue
  [ "$group" = "$features" ] && continue
  [ -f "$group/.cockpit-repo" ] || continue   # only cockpit repo groups
  slug="${group##*/}"

  for wt in "$group"/*/; do
    wt="${wt%/}"
    if [ ! -d "$wt" ] || [ ! -e "$wt/.git" ]; then continue; fi
    branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
    [ -n "$branch" ] || branch="${wt##*/}"
    printf 'W:%s\t\033[2mwktr\033[0m \033[32m●\033[0m %-26s \033[2m%s\033[0m%s\n' \
      "$wt" "$slug/$branch" "$(display_path "$wt")" "$(open_marker "$wt")"
  done
done
