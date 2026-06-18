#!/usr/bin/env bash
# Create a multi-repo "feature" set, then open it through cockpit.
#   open-feature.sh <name> <repo-path>...
#
# Default mode (clone): each repo is cloned fresh into
#   <@cockpit-worktrees-dir>/features/<name>/<repo>
# and a new branch <name> is created from the clone's default branch (main).
# This yields independent, pushable repos. Set
#   @cockpit-feature-mode worktree
# to instead add a lightweight git worktree per repo.
#
# If the feature already exists it is recreated: the folder and any cockpit
# sessions rooted in it are removed first. Clone progress is shown live so
# you can see each repo being fetched.
#
# In both modes, often-gitignored local files (.env / .env.*, AGENTS.md,
# CLAUDE.md) are copied from each source repo into the new copy — a
# clone/worktree never contains gitignored files.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd git "install git to use features"

name="$(trim_ws "${1:-}")"
shift || true

if [ -z "$name" ]; then
  cockpit_error "feature name is required"
  exit 1
fi
case "$name" in
  */* | . | ..)
    cockpit_error "invalid feature name: $name"
    exit 1
    ;;
esac
if [ "$#" -eq 0 ]; then
  cockpit_error "select at least one repo for the feature"
  exit 1
fi

feature_dir="$(features_base)/$name"
mode="$(feature_mode)"

# Recreate cleanly when the feature already exists: warn, give a moment to
# bail, then drop the old folder and its sessions. Refuse while a session
# rooted in it is attached — deleting its cwd out from under a live client is
# exactly the surprise prune.sh guards against.
if [ -e "$feature_dir" ]; then
  attached=""
  while IFS=$'\t' read -r sname satt; do
    [ "$satt" = "1" ] && attached="$attached $sname"
  done < <(sessions_under "$feature_dir")
  if [ -n "$attached" ]; then
    cockpit_error "feature '$name' has attached session(s):$attached — detach first"
    exit 1
  fi
  printf '\033[33m! recreating feature\033[0m %s — removing the old folder and its sessions\n' \
    "$(display_path "$feature_dir")"
  sleep 1.2
  remove_feature "$feature_dir" || {
    cockpit_error "refusing to remove (not under features dir): $(display_path "$feature_dir")"
    exit 1
  }
fi

mkdir -p "$feature_dir" || {
  cockpit_error "could not create feature folder: $(display_path "$feature_dir")"
  exit 1
}

# Clone <url> into <dst>, showing progress. Cleans a partial dir on failure
# so a fallback attempt can reuse the path.
clone_one() {
  local url="$1" dst="$2"
  git clone --progress "$url" "$dst" && return 0
  rm -rf "$dst"
  return 1
}

# Materialize one repo into <dest>. Returns 0 if <dest> ends up populated.
materialize_repo() {
  local repo="$1" dest="$2" base="$3" src_url

  if [ "$mode" = "worktree" ]; then
    printf '\n\033[1m→ %s\033[0m  adding worktree on %s\n' "$base" "$name"
    if git -C "$repo" show-ref --verify --quiet "refs/heads/$name"; then
      git -C "$repo" worktree add "$dest" "$name"
    else
      git -C "$repo" worktree add -b "$name" "$dest"
    fi
    [ -e "$dest/.git" ]
    return
  fi

  # clone mode: prefer the upstream remote so the new clone can push/pull,
  # falling back to cloning the local repo when there is no origin (or it
  # is unreachable).
  src_url="$(git -C "$repo" remote get-url origin 2>/dev/null)"
  printf '\n\033[1m→ %s\033[0m  cloning from %s\n' "$base" "${src_url:-$(display_path "$repo")}"
  if [ -n "$src_url" ]; then
    clone_one "$src_url" "$dest" || clone_one "$repo" "$dest"
  else
    clone_one "$repo" "$dest"
  fi
  [ -e "$dest/.git" ] || return 1

  # New branch from the default branch (the clone's current HEAD). If the
  # name already exists, just switch to it.
  git -C "$dest" checkout -q -b "$name" 2>/dev/null \
    || git -C "$dest" checkout -q "$name" 2>/dev/null \
    || true
  return 0
}

total="$#"
created=0
failed=""
used=$'\n'
for path in "$@"; do
  repo="$(git_repo_for_path "$path")" || { failed="$failed $(basename "$path")"; continue; }

  # Folder per repo, deduped so two repos that share a basename don't collide.
  base="$(safe_path_component "$(basename "$repo")")"
  sub="$base"
  i=2
  while [[ "$used" == *$'\n'"$sub"$'\n'* ]] || [ -e "$feature_dir/$sub" ]; do
    sub="$base-$i"
    i=$((i + 1))
  done
  used="$used$sub"$'\n'
  dest="$feature_dir/$sub"

  if materialize_repo "$repo" "$dest" "$sub"; then
    copy_local_files "$repo" "$dest"
    created=$((created + 1))
    printf '\033[32m✓ %s ready\033[0m\n' "$sub"
  else
    rm -rf "$dest" 2>/dev/null || true
    failed="$failed $base"
    printf '\033[31m✗ %s failed\033[0m\n' "$base"
  fi
done

if [ "$created" -eq 0 ]; then
  cockpit_error "no repos materialized${failed:+ — failed:$failed}"
  rmdir "$feature_dir" 2>/dev/null || true
  exit 1
fi

[ -n "$failed" ] && cockpit_error "some repos skipped:$failed"

printf '\n\033[1m%d/%d repos ready\033[0m — opening %s\n' \
  "$created" "$total" "$(display_path "$feature_dir")"
sleep 0.8

exec "$COCKPIT_SCRIPTS/open-project.sh" "$feature_dir"
