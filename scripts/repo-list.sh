#!/usr/bin/env bash
# Emit git-repo candidates for the multi-worktree feature picker, one per
# line:
#   <repo-path>\t<display text>
# Sources, in order: open tmux session roots, zoxide history, and
# @cockpit-project-dirs children. Only directories that contain a .git entry
# (normal repos or linked worktrees) are kept, deduped by path.
#
# Unlike project-list.sh this stats each candidate (.git check), but it only
# runs in the feature flow, not the hot prefix+o path.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

seen=$'\n'
mark_seen() { seen="${seen}${1}"$'\n'; }
is_seen() { [[ "$seen" == *$'\n'"$1"$'\n'* ]]; }

emit() {
  local dir="$1" name dp
  dir="${dir%/}"
  [ -n "$dir" ] || return 0
  is_seen "$dir" && return 0
  [ -d "$dir" ] && [ -e "$dir/.git" ] || return 0
  mark_seen "$dir"
  name="${dir##*/}"
  [ -n "$name" ] || name="root"
  case "$dir" in
    "$HOME") dp="~" ;;
    "$HOME"/*) dp="~${dir#"$HOME"}" ;;
    *) dp="$dir" ;;
  esac
  printf '%s\t\033[32m●\033[0m %-24s \033[2m%s\033[0m\n' "$dir" "$name" "$dp"
}

# 1. Open tmux session roots (cockpit-owned root if recorded, else path).
while IFS=$'\t' read -r nm path root; do
  [ -n "$nm" ] || continue
  emit "${root:-$path}"
done < <(tmux list-sessions -F $'#{session_name}\t#{session_path}\t#{@cockpit-root}' 2>/dev/null)

# 2. zoxide history (frecency-ordered).
if command -v zoxide >/dev/null 2>&1; then
  while IFS= read -r dir; do
    emit "$dir"
  done < <(zoxide query -l 2>/dev/null)
fi

# 3. Optional static project roots: every direct child of each configured dir.
project_dirs="$(get_opt "@cockpit-project-dirs" "")"
if [ -n "$project_dirs" ]; then
  IFS=':' read -ra roots <<< "$project_dirs"
  for root in "${roots[@]}"; do
    root="${root/#\~/$HOME}"
    [ -d "$root" ] || continue
    while IFS= read -r dir; do
      emit "$dir"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)
  done
fi
