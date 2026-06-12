#!/usr/bin/env bash
# Emit the merged project list, one entry per line:
#   S:<session>\t<display text>   (open sessions)
#   D:<path>\t<display text>      (directories without a session)
# Open sessions come first (◉ current / ● others), then recent zoxide
# directories that don't have a session yet (○), in zoxide frecency order.
# Extra directories from @cockpit-project-dirs (colon-separated) are
# appended.
#
# Performance matters here: fzf streams this output, and the open sessions
# at the top must render instantly. Sessions are fetched with a single tmux
# call (@cockpit-root expanded in the format string, not per-session
# show-option calls), the hot loops are pure bash (no basename/tr/awk
# forks), and lines are emitted as they're built.
#
# Kept bash-3.2 compatible (no associative arrays) — macOS ships old bash.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

# Newline-delimited set of paths already emitted.
seen=$'\n'

mark_seen() { seen="${seen}${1}"$'\n'; }
is_seen() { [[ "$seen" == *$'\n'"$1"$'\n'* ]]; }

# Emit one entry; the first 9 get a dim index — the picker binds 1-9 to
# open them instantly.
line_no=0
emit() {
  line_no=$((line_no + 1))
  if [ "$line_no" -le 9 ]; then
    printf '%s\t\033[2m%d\033[0m %s\n' "$1" "$line_no" "$2"
  else
    printf '%s\t%s\n' "$1" "$2"
  fi
}

# Pure-bash session_name_for / display_path that return via globals —
# $(...) command substitution forks a subshell per call, which adds up
# over hundreds of zoxide entries.
fast_session_name() {
  SN="${1%/}"
  SN="${SN##*/}"
  [ -n "$SN" ] || SN="root"
  SN="${SN//./_}"; SN="${SN//:/_}"; SN="${SN// /_}"; SN="${SN//\//_}"
}

fast_display_path() {
  case "$1" in
    "$HOME") DP="~" ;;
    "$HOME"/*) DP="~${1#"$HOME"}" ;;
    *) DP="$1" ;;
  esac
}

# The session this pane/client is currently on, so we can highlight it.
current_session="$(current_session)"

# 1. Open tmux sessions — a single tmux call; #{@cockpit-root} expands in
#    the format string. Roots are marked seen so the directory sections
#    below don't repeat them.
while IFS=$'\t' read -r name path root; do
  [ -n "$name" ] || continue
  root="${root:-$path}"
  mark_seen "$root"
  fast_display_path "$root"
  if [ "$name" = "$current_session" ]; then
    emit "S:$name" $'\033[1;36m◉ '"$name"$'\033[0m  \033[2m'"$DP"$'\033[0m'
  else
    emit "S:$name" $'\033[32m●\033[0m '"$name"$'  \033[2m'"$DP"$'\033[0m'
  fi
done < <(tmux list-sessions -F $'#{session_name}\t#{session_path}\t#{@cockpit-root}' 2>/dev/null)

emit_candidate() {
  local dir="$1"
  is_seen "$dir" && return 0
  mark_seen "$dir"
  fast_session_name "$dir"
  fast_display_path "$dir"
  emit "D:$dir" '○ '"$SN"$'  \033[2m'"$DP"$'\033[0m'
}

# 2. zoxide history (frecency-ordered). zoxide only stores directories it
#    has visited; stale entries are rare enough that we skip the per-entry
#    [ -d ] stat for speed — open-project.sh validates on selection anyway.
if command -v zoxide >/dev/null 2>&1; then
  while IFS= read -r dir; do
    emit_candidate "$dir"
  done < <(zoxide query -l 2>/dev/null)
fi

# 3. Optional static project roots: every direct child of each dir listed in
#    @cockpit-project-dirs is offered as a project.
project_dirs="$(get_opt "@cockpit-project-dirs" "")"
if [ -n "$project_dirs" ]; then
  IFS=':' read -ra roots <<< "$project_dirs"
  for root in "${roots[@]}"; do
    root="${root/#\~/$HOME}"
    [ -d "$root" ] || continue
    while IFS= read -r dir; do
      emit_candidate "$dir"
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)
  done
fi
