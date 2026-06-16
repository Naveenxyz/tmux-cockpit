#!/usr/bin/env bash
# Open or create a git worktree, then switch/attach through cockpit.
#   open-worktree.sh <repo-path> <branch> [dest]
# If a worktree for <branch> already exists, it is opened. Otherwise the
# default destination is @cockpit-worktrees-dir/<repo>/<branch-safe>.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd git "install git to use worktrees"

path="${1:-}"
branch="${2:-}"
dest="${3:-}"

if [ -z "$path" ] || [ ! -d "$path" ]; then
  cockpit_error "not a directory: $path"
  exit 1
fi

repo="$(git_repo_for_path "$path")" || {
  cockpit_error "not inside a git repo: $(display_path "$path")"
  exit 1
}

branch="$(trim_ws "$branch")"
if [ -z "$branch" ]; then
  cockpit_error "worktree branch/name is required"
  exit 1
fi

if ! git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1; then
  cockpit_error "invalid branch name: $branch"
  exit 1
fi

existing="$(worktree_for_branch "$repo" "$branch")"
if [ -n "$existing" ] && [ -d "$existing" ]; then
  exec "$COCKPIT_SCRIPTS/open-project.sh" "$existing"
fi

if [ -n "$dest" ]; then
  dest="$(normalize_worktree_dest "$dest")"
else
  dest="$(repo_worktree_dir "$repo")/$(safe_path_component "$branch")"
fi

if [ -e "$dest" ]; then
  if is_same_repo_worktree "$dest" "$repo"; then
    exec "$COCKPIT_SCRIPTS/open-project.sh" "$dest"
  fi
  cockpit_error "path already exists and is not a worktree for this repo: $dest"
  exit 1
fi

repo_dir="$(repo_worktree_dir "$repo")"
mkdir -p "$(dirname "$dest")" "$repo_dir"
marker="$repo_dir/.cockpit-repo"
if [ ! -f "$marker" ]; then
  common="$(common_dir_abs "$repo")"
  printf '%s\n' "$common" >"$marker"
fi

if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$repo" worktree add "$dest" "$branch" || exit 1
else
  git -C "$repo" worktree add -b "$branch" "$dest" || exit 1
fi

exec "$COCKPIT_SCRIPTS/open-project.sh" "$dest"
