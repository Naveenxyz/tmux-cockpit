#!/usr/bin/env bash
# tmux-cockpit lib: git repo / worktree helpers. Depends on util.sh
# (get_opt, expand_home_path, pane_or_shell_dir). Sourced via helpers.sh.

git_repo_for_path() {
  local path="$1"
  [ -n "$path" ] && [ -d "$path" ] || return 1
  git -C "$path" rev-parse --show-toplevel 2>/dev/null
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
  expand_home_path "$base"
}

# Root directory for multi-repo "feature" sets:
# <@cockpit-worktrees-dir>/features. Each feature is a child folder holding
# one clone (or worktree) per selected repo.
features_base() {
  printf '%s/features' "$(worktrees_base)"
}

# How features materialize each repo: "clone" (default — a fresh independent
# clone, branched from the default branch) or "worktree" (a lightweight git
# worktree of the source repo).
feature_mode() {
  local mode
  mode="$(get_opt "@cockpit-feature-mode" "clone")"
  case "$mode" in
    worktree | worktrees) printf 'worktree' ;;
    *) printf 'clone' ;;
  esac
}

# Tear down an existing feature: kill any cockpit sessions rooted at or under
# the feature folder (exact-name kills only), then remove the folder. As a
# safety measure this refuses to touch anything outside features_base.
remove_feature() {
  local dir="$1" base name root
  dir="${dir%/}"
  base="$(features_base)"
  case "$dir" in
    "$base"/?*) ;;                # must live under <worktrees>/features/
    *) return 1 ;;
  esac

  while IFS=$'\t' read -r name root; do
    [ -n "$name" ] || continue
    case "$root" in
      "$dir" | "$dir"/*) tmux kill-session -t "=$name" 2>/dev/null || true ;;
    esac
  done < <(tmux list-sessions -F $'#{session_name}\t#{@cockpit-root}' 2>/dev/null)

  rm -rf "$dir"
}

# Copy local, often-gitignored files from <src> into <dest>, preserving
# relative paths. A fresh clone or worktree never contains gitignored files,
# but they are usually required to run or work on the project. Matches, at
# any depth (skipping .git and node_modules):
#   - .env and .env.*       (environment / secrets)
#   - AGENTS.md, CLAUDE.md   (agent instructions, case-insensitive)
#
# Symlinks that match (e.g. a CLAUDE.md -> AGENTS.md link) are included and
# dereferenced (cp -L): the destination gets a real, self-contained file so
# it never dangles or points back into the source repo. Broken links are
# skipped (the copy just fails quietly).
copy_local_files() {
  local src="$1" dest="$2" f rel
  [ -d "$src" ] && [ -d "$dest" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$src"/}"
    mkdir -p "$dest/$(dirname "$rel")"
    cp -pL "$f" "$dest/$rel" 2>/dev/null || true
  done < <(find "$src" \( -name .git -o -name node_modules \) -prune \
    -o \( -type f -o -type l \) \( -name '.env' -o -name '.env.*' \
      -o -iname 'AGENTS.md' -o -iname 'CLAUDE.md' \) -print 2>/dev/null)
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

worktree_for_branch() {
  local repo="$1" branch="$2"
  git -C "$repo" worktree list --porcelain | awk -v branch="refs/heads/$branch" '
    /^worktree / { path = substr($0, 10); next }
    /^branch / && substr($0, 8) == branch { print path; exit }
  '
}

normalize_worktree_dest() {
  local dest="$1"
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
