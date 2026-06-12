#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every default agent module must exist and define the interface
# (<name>_procs — see scripts/agents/claude.sh).
for agent in claude codex opencode pi; do
  module="$ROOT/scripts/agents/$agent.sh"
  [ -f "$module" ] || { printf 'not ok - missing agent module: %s\n' "$agent" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$module"
  eval "procs=\"\${${agent}_procs:-}\""
  # shellcheck disable=SC2154
  [ -n "$procs" ] || { printf 'not ok - %s_procs not defined\n' "$agent" >&2; exit 1; }
done

# agent-list.sh with no tmux server (stubbed empty) emits nothing and
# exits cleanly.
TMPDIR_T="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-agents.XXXXXX")"
trap 'rm -rf "$TMPDIR_T"' EXIT HUP INT TERM
mkdir -p "$TMPDIR_T/bin"
cat >"$TMPDIR_T/bin/tmux" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TMPDIR_T/bin/tmux"
out="$(PATH="$TMPDIR_T/bin:$PATH" "$ROOT/scripts/agent-list.sh")"
[ -z "$out" ] || { printf 'not ok - agent-list without panes should emit nothing\n' >&2; exit 1; }

# Process-tree detection, with stubbed tmux + ps:
#   pane %1 pid 100 — the agent IS the pane root (tmux new-window pi)
#   pane %2 pid 200 — agent one level down  (zsh -> claude)
#   pane %3 pid 300 — plain shell, no agent
cat >"$TMPDIR_T/bin/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    printf '%%1\t100\tproj\t1\tpi\t00\n'
    printf '%%2\t200\tproj\t2\tclaude\t00\n'
    printf '%%3\t300\tproj\t3\tzsh\t00\n'
    ;;
  display-message) printf 'other\n' ;;
esac
exit 0
STUB
cat >"$TMPDIR_T/bin/ps" <<'STUB'
#!/usr/bin/env bash
printf '  100     1 pi\n'
printf '  200     1 zsh\n'
printf '  201   200 claude\n'
printf '  300     1 zsh\n'
STUB
chmod +x "$TMPDIR_T/bin/tmux" "$TMPDIR_T/bin/ps"

out="$(PATH="$TMPDIR_T/bin:$PATH" "$ROOT/scripts/agent-list.sh")"
case "$out" in
  *'A:%1'*) ;;
  *) printf 'not ok - agent as pane root process is detected\nOutput:\n%s\n' "$out" >&2; exit 1 ;;
esac
case "$out" in
  *'A:%2'*) ;;
  *) printf 'not ok - agent below a shell is detected\nOutput:\n%s\n' "$out" >&2; exit 1 ;;
esac
case "$out" in
  *'A:%3'*) printf 'not ok - plain shell pane must not be listed\nOutput:\n%s\n' "$out" >&2; exit 1 ;;
esac

printf 'ok - agents\n'
