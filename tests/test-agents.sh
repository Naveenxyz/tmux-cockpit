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

printf 'ok - agents\n'
