#!/usr/bin/env bash
# Emit every AI-agent pane, one entry per line, ordered by project
# (session, then window):
#   A:<pane_id>\t<display text>
# With --current, only the current session's agent panes are listed.
# The first 9 entries get a dim index for the picker's digit shortcuts.
#
# Detection is observational — no agent-side hooks or config: one `ps`
# snapshot, one awk pass that walks each pane's process tree looking for
# an agent process name (tmux's #{pane_current_command} is useless here:
# Claude's launcher renames itself to its version number, pi shows up as
# "node").
#
# Agents are pluggable: scripts/agents/<name>.sh modules (see
# agents/claude.sh for the interface), selected via @cockpit-agents
# (default: "claude codex opencode pi").
#
# Kept bash-3.2 compatible (no associative arrays) — macOS ships old bash.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

only_current=""
[ "$1" = "--current" ] && only_current=1

agents="$(get_opt "@cockpit-agents" "claude codex opencode pi")"

# Load agent modules and build the "proc:agent" map for the awk pass.
proc_map=""
for agent in $agents; do
  module="$COCKPIT_SCRIPTS/agents/$agent.sh"
  [ -f "$module" ] || continue
  # shellcheck disable=SC1090
  source "$module"
  eval "procs=\"\${${agent}_procs:-$agent}\""
  # shellcheck disable=SC2154
  for proc in $procs; do
    proc_map="$proc_map$proc:$agent "
  done
done
[ -n "$proc_map" ] || exit 0

current_session="$(current_session)"

# All panes, one tmux call — tmux lists them grouped by session (sorted),
# then window, which is exactly the project ordering we want.
if [ -n "$only_current" ]; then
  panes="$(tmux list-panes -s -t "=$current_session" -F \
    $'#{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{window_name}\t#{?pane_active,1,0}#{?window_active,1,0}' \
    2>/dev/null)"
else
  panes="$(tmux list-panes -a -F \
    $'#{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{window_name}\t#{?pane_active,1,0}#{?window_active,1,0}' \
    2>/dev/null)"
fi
[ -n "$panes" ] || exit 0

pane_pids=""
while IFS=$'\t' read -r _ pid _; do
  pane_pids="$pane_pids$pid "
done <<< "$panes"

# One ps snapshot, one awk BFS per pane: find the first descendant of the
# pane's root process whose comm basename names an agent.
matches="$(ps -axo pid=,ppid=,comm= | awk -v pids="$pane_pids" -v map="$proc_map" '
  {
    pid = $1; ppid = $2; comm = $3
    sub(".*/", "", comm)
    children[ppid] = children[ppid] " " pid
    name[pid] = comm
  }
  END {
    n = split(map, entries, " ")
    for (i = 1; i <= n; i++) {
      split(entries[i], kv, ":")
      agent_of[kv[1]] = kv[2]
    }
    m = split(pids, roots, " ")
    for (i = 1; i <= m; i++) {
      # BFS from the pane root (included: `tmux new-window claude` makes
      # the agent the root itself), depth-limited — agents otherwise sit
      # one or two levels down (shell -> launcher -> agent).
      head = 1; tail = 1; queue[1] = roots[i]; depth[roots[i]] = 0
      found = ""
      while (head <= tail && found == "") {
        cur = queue[head]; head++
        if (name[cur] in agent_of) {
          found = agent_of[name[cur]]
          break
        }
        if (depth[cur] >= 5) continue
        k = split(children[cur], kids, " ")
        for (j = 1; j <= k; j++) {
          if (kids[j] == "") continue
          tail++; queue[tail] = kids[j]; depth[kids[j]] = depth[cur] + 1
        }
      }
      delete queue; delete depth
      if (found != "") print roots[i], found
    }
  }
')"

# Leading newline so the lookup below can anchor every line uniformly.
matches=$'\n'"$matches"

agent_for_pid() {
  AGENT=""
  case "$matches" in
    *$'\n'"$1 "*)
      AGENT="${matches#*$'\n'"$1" }"
      AGENT="${AGENT%%$'\n'*}"
      ;;
  esac
}

line_no=0
while IFS=$'\t' read -r pane_id pane_pid session win_idx win_name active; do
  [ -n "$pane_id" ] || continue
  agent_for_pid "$pane_pid"
  [ -n "$AGENT" ] || continue

  here=""
  [ "$session" = "$current_session" ] && [ "$active" = "11" ] && here=$' \033[2m(here)\033[0m'

  line_no=$((line_no + 1))
  idx="  "
  [ "$line_no" -le 9 ] && idx="$line_no "

  printf 'A:%s\t\033[2m%s\033[0m\033[32m●\033[0m %-9s \033[1m%-20s\033[0m \033[2m%s:%s\033[0m%s\n' \
    "$pane_id" "$idx" "$AGENT" "$session" "$win_idx" "$win_name" "$here"
done <<< "$panes"
