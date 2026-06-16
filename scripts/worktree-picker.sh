#!/usr/bin/env bash
# Git worktree picker/creator for a project entry. Invoked from the project
# picker with ctrl-w. Lists worktrees for the selected repo and can create a
# new one under @cockpit-worktrees-dir (default: ~/worktrees).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd git "install git to use worktrees"
require_cmd fzf "install it (brew install fzf) to use the worktree picker"

query=""
if [ "$1" = "--query" ]; then
  query="${2:-}"
  shift 2
fi

target="${1:-}"
if [ -z "$target" ] && [ -n "$query" ]; then
  typed_dir="$(resolve_typed_dir "$query" 2>/dev/null || true)"
  [ -n "$typed_dir" ] && target="D:$typed_dir"
fi

[ -n "$target" ] || exit 0
target="${target%%$'\t'*}"
parse_target "$target"

if [ "$TARGET_KIND" = "session" ]; then
  path="$(session_path_of "$TARGET_VALUE")"
else
  path="$TARGET_VALUE"
fi

if [ -z "$path" ] || [ ! -d "$path" ]; then
  cockpit_error "not a directory: $path"
  sleep 1
  exit 1
fi

repo="$(git_repo_for_path "$path")" || {
  cockpit_error "not inside a git repo: $(display_path "$path")"
  sleep 1
  exit 1
}

choose_branch() {
  local result query selection branch
  # fzf exits non-zero when the typed query has no match, even with
  # --print-query. That is exactly how users create a new branch, so keep
  # the printed query and only treat an empty result as cancel.
  result="$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null \
    | fzf \
      --print-query \
      --layout=reverse \
      --prompt='branch ❯ ' \
      --header='type a new branch name, or pick an existing branch · esc: cancel' \
      --preview "git -C '$repo' log --oneline --decorate --max-count=12 {1} 2>/dev/null || true" \
      --preview-window 'right,55%,border-left')" || true
  [ -n "$result" ] || return 1

  query="${result%%$'\n'*}"
  if [ "$result" != "$query" ]; then
    selection="${result#*$'\n'}"
    selection="${selection%%$'\n'*}"
  else
    selection=""
  fi

  branch="$(trim_ws "${selection:-$query}")"
  [ -n "$branch" ] || return 1
  git -C "$repo" check-ref-format --branch "$branch" >/dev/null 2>&1 || {
    cockpit_error "invalid branch name: $branch"
    sleep 1.6
    return 1
  }
  printf '%s' "$branch"
}

choose_location() {
  local default_dir="$1" result query selection dest
  # Same as choose_branch: an edited custom path can make fzf exit non-zero,
  # but --print-query still gives us the path the user typed.
  result="$(printf '%s\tdefault\n' "$default_dir" \
    | fzf \
      --phony \
      --print-query \
      --query "$default_dir" \
      --delimiter=$'\t' \
      --with-nth=1 \
      --layout=reverse \
      --prompt='location ❯ ' \
      --header='edit the path, or press enter for the default · esc: cancel' \
      --preview "printf 'worktree path:\n\n%s\n' {q}" \
      --preview-window 'right,55%,border-left')" || true
  [ -n "$result" ] || return 1

  query="${result%%$'\n'*}"
  if [ "$result" != "$query" ]; then
    selection="${result#*$'\n'}"
    selection="${selection%%$'\n'*}"
    selection="${selection%%$'\t'*}"
  else
    selection=""
  fi

  dest="$(trim_ws "${query:-$selection}")"
  [ -n "$dest" ] || dest="$default_dir"
  normalize_worktree_dest "$dest"
}

create_worktree() {
  local branch default_dir dest repo_dir

  branch="$(choose_branch)" || exit 0
  repo_dir="$(repo_worktree_dir "$repo")"
  default_dir="$repo_dir/$(safe_path_component "$branch")"
  dest="$(choose_location "$default_dir")" || exit 0

  clear
  printf 'Creating worktree\n\n  repo:   %s\n  branch: %s\n  path:   %s\n\n' \
    "$(display_path "$repo")" "$branch" "$(display_path "$dest")"
  exec "$COCKPIT_SCRIPTS/open-worktree.sh" "$repo" "$branch" "$dest"
}

emit_worktrees() {
  printf 'C:%s\t\033[1;32m+ create worktree\033[0m  \033[2m%s\033[0m\n' "$repo" "$(display_path "$(repo_worktree_dir "$repo")")"

  git -C "$repo" worktree list --porcelain | awk -v home="$HOME" '
    function display(p) { if (p == home) return "~"; if (index(p, home "/") == 1) return "~" substr(p, length(home) + 1); return p }
    function flush() {
      if (path == "") return
      label = branch
      sub("^refs/heads/", "", label)
      if (label == "") label = "detached"
      current = (path == repo ? " \033[2m(main)\033[0m" : "")
      printf "D:%s\t\033[32m●\033[0m %-24s \033[2m%s\033[0m%s\n", path, label, display(path), current
    }
    /^worktree / { flush(); path = substr($0, 10); branch = ""; next }
    /^branch / { branch = substr($0, 8); next }
    /^detached$/ { branch = "detached"; next }
    END { flush() }
  ' repo="$repo"
}

selection="$(emit_worktrees | fzf \
  --ansi \
  --delimiter=$'\t' \
  --with-nth=2 \
  --layout=reverse \
  --prompt='worktree ❯ ' \
  --header='enter: open/create · esc: cancel' \
  --preview "'$COCKPIT_SCRIPTS/preview.sh' {1}" \
  --preview-window 'right,55%,border-left')"

[ -n "$selection" ] || exit 0
target="${selection%%$'\t'*}"
case "$target" in
  C:*) create_worktree ;;
  *) exec "$COCKPIT_SCRIPTS/open-project.sh" "$target" ;;
esac
