#!/usr/bin/env bash
# Shared helpers for tmux-cockpit. Sourced by every script.

# Used by scripts that source helpers.sh.
# shellcheck disable=SC2034
COCKPIT_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_opt() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${value:-$2}"
}

# Sanitize one path component into a valid, target-friendly tmux session
# name component. Keep '-' and '_' readable; replace separators that confuse
# tmux targets or shells. We intentionally keep '/' between components in
# candidate names below because names like "repo/branch" are much clearer
# than "repo_branch".
sanitize_session_component() {
  local name
  name="$(printf '%s' "$1" | tr '.: ' '___')"
  [ -n "$name" ] || name="root"
  printf '%s' "$name"
}

# Backwards-compatible single-path session name: the directory basename.
session_name_for() {
  local base
  base="$(basename "$1")"
  [ "$base" = "/" ] && base="root"
  sanitize_session_component "$base"
}

expand_home_path() {
  case "$1" in
    ~) printf '%s' "$HOME" ;;
    ~/*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Print readable session-name candidates for <path>, from least to most
# specific. For /Users/me/work/api:
#   api
#   work/api
#   me/work/api
#   Users/me/work/api
# Numeric suffixes are only a last resort; parent context is more readable
# for same-named repos and worktrees. Paths under @cockpit-worktrees-dir
# start at repo/branch (not just branch), so worktree sessions are easy to
# trace back to their repo.
session_name_candidates_for_path() {
  local path="$1" rel part name rest worktrees_dir under_worktrees
  path="${path%/}"
  [ -n "$path" ] || path="/"

  if [ "$path" = "/" ]; then
    printf 'root\n'
    return 0
  fi

  worktrees_dir="$(expand_home_path "$(get_opt "@cockpit-worktrees-dir" "$HOME/worktrees")")"
  worktrees_dir="${worktrees_dir%/}"
  under_worktrees=""
  case "$path" in
    "$worktrees_dir"/*/*) under_worktrees=1 ;;
  esac

  rel="${path#/}"
  name=""
  while [ -n "$rel" ]; do
    part="${rel##*/}"
    if [ -n "$name" ]; then
      name="$(sanitize_session_component "$part")/$name"
    else
      name="$(sanitize_session_component "$part")"
    fi
    if [ -z "$under_worktrees" ] || [[ "$name" == */* ]]; then
      printf '%s\n' "$name"
    fi
    [ "$rel" = "$part" ] && break
    rest="${rel%/*}"
    [ "$rest" = "$rel" ] && break
    rel="$rest"
  done
}

session_exists() {
  tmux has-session -t "=$1" 2>/dev/null
}

# Note: set-option/show-option take a pane target in tmux >= 3.x, so the '='
# exact-match session prefix is not valid here — pass the bare session name.
session_root() {
  tmux show-option -t "$1" -qv "@cockpit-root" 2>/dev/null
}

# Resolve the session name that owns <path>. If a different project with the
# same basename already took the name, append -2, -3, ... Sessions without a
# recorded root (created outside cockpit) are treated as a match so we attach
# instead of duplicating.
session_for_root() {
  local path="$1"
  tmux list-sessions -F $'#{session_name}\t#{@cockpit-root}' 2>/dev/null \
    | awk -F'\t' -v p="$path" '$2 == p {print $1; exit}'
}

resolve_session_for_path() {
  local path="$1" existing name root base i

  existing="$(session_for_root "$path")"
  if [ -n "$existing" ]; then
    printf '%s' "$existing"
    return 0
  fi

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! session_exists "$name"; then
      printf '%s' "$name"
      return 0
    fi
    root="$(session_root "$name")"
    if [ -z "$root" ] || [ "$root" = "$path" ]; then
      printf '%s' "$name"
      return 0
    fi
  done < <(session_name_candidates_for_path "$path")

  base="$(session_name_for "$path")"
  i=2
  name="${base}-${i}"
  while session_exists "$name"; do
    root="$(session_root "$name")"
    if [ -z "$root" ] || [ "$root" = "$path" ]; then
      printf '%s' "$name"
      return 0
    fi
    i=$((i + 1))
    name="${base}-${i}"
  done
  printf '%s' "$name"
}

# Parse an @cockpit-auto-commands string into AUTO_CMDS / AUTO_NAMES.
# Format: command:name;command:name;...  The name is optional (defaults to
# the command's first word). A command may be wrapped in single or double
# quotes so it can contain ':' or ';' (e.g. "npm run dev -- --port=3000").
# Kept bash-3.2 compatible.
parse_auto_commands() {
  AUTO_CMDS=() AUTO_NAMES=()
  local s="$1" len i ch quote="" field="cmd" cmd="" name=""

  _trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
  }

  _flush() {
    cmd="$(_trim "$cmd")"
    name="$(_trim "$name")"
    [ -n "$cmd" ] || { name=""; field="cmd"; return 0; }
    [ -n "$name" ] || name="${cmd%% *}"
    AUTO_CMDS+=("$cmd")
    AUTO_NAMES+=("$name")
    cmd="" name="" field="cmd"
  }

  len=${#s}
  i=0
  while [ "$i" -lt "$len" ]; do
    ch="${s:$i:1}"
    if [ -n "$quote" ]; then
      if [ "$ch" = "$quote" ]; then
        quote=""
      elif [ "$field" = "cmd" ]; then
        cmd+="$ch"
      else
        name+="$ch"
      fi
    else
      case "$ch" in
        \'|\") quote="$ch" ;;
        :) if [ "$field" = "cmd" ]; then field="name"; else name+="$ch"; fi ;;
        \;) _flush ;;
        *) if [ "$field" = "cmd" ]; then cmd+="$ch"; else name+="$ch"; fi ;;
      esac
    fi
    i=$((i + 1))
  done
  _flush
  unset -f _trim _flush
}

# Ensure a session exists for <path> (must be absolute), creating it if
# needed. With nothing configured this is the default tmux experience: one
# plain window in the project root. If @cockpit-auto-commands is set, each
# entry becomes its own window (tab) named after the entry and running its
# command, plus one extra plain-shell window (auto-named by tmux). Prints
# the session name.
ensure_session_for_path() {
  local path="$1" session auto first_pane pane_id idx cmd name
  session="$(resolve_session_for_path "$path")"

  if ! session_exists "$session"; then
    # Create the session before reading any @cockpit-* option: if no tmux
    # server is running yet (e.g. `cockpit foo` right after boot), options
    # only exist after the server starts and sources ~/.tmux.conf — which
    # this new-session triggers.
    first_pane="$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -c "$path")"
    tmux set-option -t "$session" "@cockpit-root" "$path"

    auto="$(get_opt "@cockpit-auto-commands" "")"
    parse_auto_commands "$auto"

    idx=0
    while [ "$idx" -lt "${#AUTO_CMDS[@]}" ]; do
      cmd="${AUTO_CMDS[$idx]}"
      name="${AUTO_NAMES[$idx]}"
      if [ "$idx" -eq 0 ]; then
        # Claim the initial window (rename also turns off automatic-rename,
        # so the name sticks like new-window -n).
        pane_id="$first_pane"
        tmux rename-window -t "$pane_id" "$name"
      else
        pane_id="$(tmux new-window -d -P -F '#{pane_id}' -t "=$session:" -c "$path" -n "$name")"
      fi
      # Typed into the interactive shell (send-keys), so user aliases and
      # shell functions resolve exactly as if typed by hand. No existence
      # pre-check: a bash-side 'command -v' can't see zsh aliases/functions,
      # and the shell itself reports unknown commands in the window anyway.
      tmux send-keys -t "$pane_id" "$cmd" C-m
      idx=$((idx + 1))
    done

    # Extra plain-shell window when auto commands were launched. Unnamed:
    # tmux's automatic-rename keeps the name tracking whatever runs in it.
    if [ "${#AUTO_CMDS[@]}" -gt 0 ]; then
      tmux new-window -d -t "=$session:" -c "$path"
    fi
  fi

  printf '%s' "$session"
}

# Find the existing session for <path>, if any. Prints the name and returns 0,
# or returns 1 when no session owns this path.
find_session_for_path() {
  local path="$1" name
  name="$(resolve_session_for_path "$path")"
  if session_exists "$name"; then
    printf '%s' "$name"
    return 0
  fi
  return 1
}

# The session this process belongs to. Prefer TMUX_PANE so the answer is
# tied to the pane this script runs in, not the most recent client.
current_session() {
  if [ -n "${TMUX_PANE:-}" ]; then
    tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null
  else
    tmux display-message -p '#{session_name}' 2>/dev/null
  fi
}

# The project root of a session: @cockpit-root if recorded, else the
# session's path.
session_path_of() {
  local root
  root="$(session_root "$1")"
  if [ -n "$root" ]; then
    printf '%s' "$root"
    return 0
  fi
  tmux list-sessions -F $'#{session_name}\t#{session_path}' 2>/dev/null \
    | awk -F'\t' -v s="$1" '$1 == s {print $2; exit}'
}

# List entries carry a typed target in field 1: "S:<session>" for open
# sessions, "D:<path>" for directories. Parse one into TARGET_KIND
# (session|dir) and TARGET_VALUE; a bare path is treated as a directory.
parse_target() {
  case "$1" in
    S:*) TARGET_KIND=session TARGET_VALUE="${1#S:}" ;;
    D:*) TARGET_KIND=dir     TARGET_VALUE="${1#D:}" ;;
    *)   TARGET_KIND=dir     TARGET_VALUE="$1" ;;
  esac
}

cockpit_error() {
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux display-message "tmux-cockpit: $*" 2>/dev/null || printf 'tmux-cockpit: %s\n' "$*" >&2
  else
    printf 'tmux-cockpit: %s\n' "$*" >&2
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    cockpit_error "'$1' is required — $2"
    exit 1
  fi
}

# bash 3.2 mangles ${var/#$HOME/\~}, so shorten $HOME the portable way.
display_path() {
  case "$1" in
    "$HOME") printf '~' ;;
    "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

trim_ws() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

pane_or_shell_dir() {
  local dir
  dir="$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || true)"
  [ -n "$dir" ] || dir="$PWD"
  printf '%s' "$dir"
}

# Resolve a user-typed picker query to a real directory, but only for
# path-like input. This lets prefix+o accept ~/Desktop/foo, ../repo, or
# src/project without treating ordinary fuzzy queries as paths.
resolve_typed_dir() {
  local q="$1" candidate
  q="$(trim_ws "$q")"
  [ -n "$q" ] || return 1

  case "$q" in
    ~) candidate="$HOME" ;;
    ~/*) candidate="$HOME/${q#~/}" ;;
    /*) candidate="$q" ;;
    .|..|./*|../*) candidate="$(pane_or_shell_dir)/$q" ;;
    */*) candidate="$(pane_or_shell_dir)/$q" ;;
    *) return 1 ;;
  esac

  [ -d "$candidate" ] || return 1
  (cd "$candidate" && pwd)
}

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
