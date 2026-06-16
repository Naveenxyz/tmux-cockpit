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

repo="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || {
  cockpit_error "not inside a git repo: $(display_path "$path")"
  sleep 1
  exit 1
}

common_dir_abs() {
  local root="$1" common
  common="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    /*) printf '%s' "$common" ;;
    *)  (cd "$root/$common" && pwd) ;;
  esac
}

safe_path_component() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '/: ' '---')"
  [ -n "$s" ] || s="worktree"
  printf '%s' "$s"
}

path_hash() {
  cksum | awk '{ print $1 }'
}

worktrees_base() {
  local base
  base="$(get_opt "@cockpit-worktrees-dir" "$HOME/worktrees")"
  case "$base" in
    ~) base="$HOME" ;;
    ~/*) base="$HOME/${base#~/}" ;;
  esac
  printf '%s' "$base"
}

repo_worktree_dir() {
  local root="$1" base slug dir marker common hash
  base="$(worktrees_base)"
  slug="$(safe_path_component "$(basename "$root")")"
  dir="$base/$slug"
  marker="$dir/.cockpit-repo"
  common="$(common_dir_abs "$root")"

  if [ -e "$dir" ]; then
    if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$common" ]; then
      printf '%s' "$dir"
      return 0
    fi
    hash="$(printf '%s' "$common" | path_hash)"
    dir="$base/$slug-$hash"
  fi
  printf '%s' "$dir"
}

is_same_repo_worktree() {
  local candidate="$1" root="$2" a b
  [ -d "$candidate" ] || return 1
  a="$(common_dir_abs "$candidate" 2>/dev/null)" || return 1
  b="$(common_dir_abs "$root" 2>/dev/null)" || return 1
  [ "$a" = "$b" ]
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
  case "$dest" in
    ~) dest="$HOME" ;;
    ~/*) dest="$HOME/${dest#~/}" ;;
  esac
  case "$dest" in
    /*) ;;
    *) dest="$(pane_or_shell_dir)/$dest" ;;
  esac
  printf '%s' "$dest"
}

create_worktree() {
  local branch default_dir dest repo_dir marker common parent

  branch="$(choose_branch)" || exit 0
  repo_dir="$(repo_worktree_dir "$repo")"
  default_dir="$repo_dir/$(safe_path_component "$branch")"
  dest="$(choose_location "$default_dir")" || exit 0

  if [ -e "$dest" ]; then
    if is_same_repo_worktree "$dest" "$repo"; then
      exec "$COCKPIT_SCRIPTS/open-project.sh" "$dest"
    fi
    cockpit_error "path already exists and is not a worktree for this repo: $dest"
    sleep 2.4
    exit 1
  fi

  parent="$(dirname "$dest")"
  mkdir -p "$parent" "$repo_dir"
  common="$(common_dir_abs "$repo")"
  marker="$repo_dir/.cockpit-repo"
  [ -f "$marker" ] || printf '%s\n' "$common" >"$marker"

  clear
  printf 'Creating worktree\n\n  repo:   %s\n  branch: %s\n  path:   %s\n\n' \
    "$(display_path "$repo")" "$branch" "$(display_path "$dest")"

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo" worktree add "$dest" "$branch" || { printf '\nfailed; press any key to close... '; read -r -n 1 _; exit 1; }
  else
    git -C "$repo" worktree add -b "$branch" "$dest" || { printf '\nfailed; press any key to close... '; read -r -n 1 _; exit 1; }
  fi

  exec "$COCKPIT_SCRIPTS/open-project.sh" "$dest"
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
