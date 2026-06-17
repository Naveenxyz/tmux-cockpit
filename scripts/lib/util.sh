#!/usr/bin/env bash
# tmux-cockpit lib: generic utilities (options, paths, messaging, fzf-entry
# parsing). No git/session knowledge lives here. Sourced via helpers.sh.

get_opt() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${value:-$2}"
}

expand_home_path() {
  case "$1" in
    ~) printf '%s' "$HOME" ;;
    ~/*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    *) printf '%s' "$1" ;;
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

# List entries carry a typed target in field 1: "S:<session>" for open
# sessions, "D:<path>" for directories. Parse one into TARGET_KIND
# (session|dir) and TARGET_VALUE; a bare path is treated as a directory.
# Consumers read TARGET_KIND/TARGET_VALUE after calling.
# shellcheck disable=SC2034
parse_target() {
  case "$1" in
    S:*) TARGET_KIND=session TARGET_VALUE="${1#S:}" ;;
    D:*) TARGET_KIND=dir     TARGET_VALUE="${1#D:}" ;;
    *)   TARGET_KIND=dir     TARGET_VALUE="$1" ;;
  esac
}
