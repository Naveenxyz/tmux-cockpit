#!/usr/bin/env bash
# Shared helpers for tmux-cockpit. Sourced by every script.

COCKPIT_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

get_opt() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${value:-$2}"
}

# tmux session names cannot contain '.' or ':' — sanitize a directory
# basename into a valid session name.
session_name_for() {
  basename "$1" | tr '.: ' '___'
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
resolve_session_for_path() {
  local path="$1" base name root i
  base="$(session_name_for "$path")"
  name="$base"
  i=2
  while session_exists "$name"; do
    root="$(session_root "$name")"
    if [ -z "$root" ] || [ "$root" = "$path" ]; then
      printf '%s' "$name"
      return 0
    fi
    name="${base}-${i}"
    i=$((i + 1))
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
  local path="$1" session auto pane_id idx cmd name
  session="$(resolve_session_for_path "$path")"

  if ! session_exists "$session"; then
    auto="$(get_opt "@cockpit-auto-commands" "")"
    parse_auto_commands "$auto"

    if [ "${#AUTO_CMDS[@]}" -eq 0 ]; then
      # Plain tmux session — no auto commands, no custom layout.
      tmux new-session -d -s "$session" -c "$path"
      tmux set-option -t "$session" "@cockpit-root" "$path"
      printf '%s' "$session"
      return 0
    fi

    idx=0
    while [ "$idx" -lt "${#AUTO_CMDS[@]}" ]; do
      cmd="${AUTO_CMDS[$idx]}"
      name="${AUTO_NAMES[$idx]}"
      if [ "$idx" -eq 0 ]; then
        pane_id="$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -c "$path" -n "$name")"
        tmux set-option -t "$session" "@cockpit-root" "$path"
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

    # Extra plain-shell window. No -n: tmux's automatic-rename keeps the
    # name tracking whatever runs in it.
    tmux new-window -d -t "=$session:" -c "$path"
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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    tmux display-message "tmux-cockpit: '$1' is required — $2"
    exit 1
  fi
}

# bash 3.2 mangles ${var/#$HOME/\~}, so shorten $HOME the portable way.
display_path() {
  case "$1" in
    "$HOME"*) printf '~%s' "${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}
