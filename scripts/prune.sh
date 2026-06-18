#!/usr/bin/env bash
# Prune a cockpit-managed worktree or feature: kill its tmux sessions, remove
# it from git correctly, and delete its folder. Used by the manage picker
# (ctrl-x) and the CLI (`cockpit -w --rm`, `cockpit -f --rm`).
#
# Targets:
#   prune.sh W:<path>              a single worktree (manage-list tag)
#   prune.sh F:<path>              a feature folder (manage-list tag)
#   prune.sh --worktree <repo> <branch>   resolve repo's worktree for <branch>
#   prune.sh --feature <name>             the feature named <name>
#
# Confirms before destroying anything unless COCKPIT_YES=1. Refuses while a
# session rooted in the target is still attached (detach it first).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd git "install git to prune worktrees and features"

# Read a y/N answer from the controlling terminal. Auto-yes with COCKPIT_YES=1
# (CLI --yes, and tests).
confirm() {
  local ans
  [ "${COCKPIT_YES:-}" = "1" ] && return 0
  printf '%s [y/N] ' "$1"
  if [ -r /dev/tty ]; then
    read -r ans </dev/tty || ans=""
  else
    read -r ans || ans=""
  fi
  case "$ans" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Refuse to prune while a rooted session is attached: deleting its directory
# out from under a live client is exactly the surprise cockpit avoids
# elsewhere (see kill-session.sh).
guard_attached() {
  local dir="$1" name att attached=""
  while IFS=$'\t' read -r name att; do
    [ "$att" = "1" ] && attached="$attached $name"
  done < <(sessions_under "$dir")
  if [ -n "$attached" ]; then
    cockpit_error "won't prune — attached session(s):$attached — detach first"
    sleep 1.6
    return 1
  fi
}

prune_feature() {
  local dir="$1" base
  dir="${dir%/}"
  base="$(features_base)"
  case "$dir" in
    "$base"/?*) ;;
    *) cockpit_error "not a feature under $(display_path "$base"): $dir"; sleep 1.6; return 1 ;;
  esac
  if [ ! -d "$dir" ]; then
    cockpit_error "no such feature: $(display_path "$dir")"
    sleep 1.6
    return 1
  fi

  printf '\033[1mPrune feature\033[0m %s\n' "$(display_path "$dir")"
  printf '  removes the folder and its worktrees/clones, and kills its sessions.\n\n'

  guard_attached "$dir" || return 1
  confirm "Prune feature $(basename "$dir")?" || { printf 'cancelled\n'; return 0; }

  if remove_feature "$dir"; then
    printf '\033[32m✓ pruned feature %s\033[0m\n' "$(basename "$dir")"
  else
    cockpit_error "could not remove feature: $(display_path "$dir")"
    sleep 1.6
    return 1
  fi
}

prune_worktree() {
  local path="$1" main err
  path="${path%/}"
  if [ ! -d "$path" ]; then
    cockpit_error "no such worktree: $(display_path "$path")"
    sleep 1.6
    return 1
  fi
  path="$(cd "$path" && pwd -P)"
  main="$(worktree_main_repo "$path")" || {
    cockpit_error "not inside a git repo: $(display_path "$path")"
    sleep 1.6
    return 1
  }
  if [ "$main" = "$path" ]; then
    cockpit_error "refusing to prune the main worktree: $(display_path "$path")"
    sleep 1.6
    return 1
  fi

  printf '\033[1mPrune worktree\033[0m %s\n' "$(display_path "$path")"
  printf '  source repo: %s\n\n' "$(display_path "$main")"

  guard_attached "$path" || return 1
  confirm "Prune worktree $(display_path "$path")?" || { printf 'cancelled\n'; return 0; }

  kill_sessions_under "$path"

  # Detect failure by exit status, not output: git is silent on success, so
  # a stray warning must not be mistaken for a refusal.
  if ! err="$(git -C "$main" worktree remove "$path" 2>&1)"; then
    # git refuses to remove a dirty/untracked worktree without --force.
    printf '\033[33m%s\033[0m\n' "$err"
    confirm "Force-remove (this discards uncommitted changes)?" || { printf 'kept\n'; return 0; }
    git -C "$main" worktree remove --force "$path" || {
      cockpit_error "force remove failed: $(display_path "$path")"
      sleep 1.6
      return 1
    }
  fi
  git -C "$main" worktree prune 2>/dev/null || true
  cleanup_empty_repo_group "$path"
  printf '\033[32m✓ pruned worktree %s\033[0m\n' "$(display_path "$path")"
}

case "${1:-}" in
  F:*) prune_feature "${1#F:}" ;;
  W:*) prune_worktree "${1#W:}" ;;
  --feature)
    shift
    name="$(trim_ws "${1:-}")"
    [ -n "$name" ] || { cockpit_error "--feature needs a name"; exit 2; }
    prune_feature "$(features_base)/$name"
    ;;
  --worktree)
    shift
    repo="${1:-}"
    branch="${2:-}"
    if [ -z "$repo" ] || [ -z "$branch" ]; then
      cockpit_error "--worktree needs <repo> <branch>"
      exit 2
    fi
    repo="$(git_repo_for_path "$repo")" || { cockpit_error "not a git repo: $repo"; exit 1; }
    wt="$(worktree_for_branch "$repo" "$branch")"
    [ -n "$wt" ] || { cockpit_error "no worktree for branch '$branch' in $(display_path "$repo")"; exit 1; }
    prune_worktree "$wt"
    ;;
  "") exit 0 ;;
  *) cockpit_error "not a prunable entry: $1"; exit 1 ;;
esac
