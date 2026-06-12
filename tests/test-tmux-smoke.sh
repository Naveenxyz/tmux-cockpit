#!/usr/bin/env bash
set -e

if ! command -v tmux >/dev/null 2>&1; then
  printf 'ok - tmux smoke skipped (tmux not installed)\n'
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-tmux.XXXXXX")"
REAL_TMUX="$(command -v tmux)"
SOCKET="cockpit-test-$$"
SESSION=""

cleanup() {
  if [ -n "$SESSION" ]; then
    PATH="$TMPDIR/bin:$PATH" tmux kill-session -t "=$SESSION" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMPDIR/bin" "$TMPDIR/my.project"
cat >"$TMPDIR/bin/tmux" <<'STUB'
#!/usr/bin/env bash
exec "$COCKPIT_REAL_TMUX" -f /dev/null -L "$COCKPIT_TEST_SOCKET" "$@"
STUB
chmod +x "$TMPDIR/bin/tmux"

export COCKPIT_REAL_TMUX="$REAL_TMUX"
export COCKPIT_TEST_SOCKET="$SOCKET"
export PATH="$TMPDIR/bin:$PATH"

# shellcheck source=../scripts/helpers.sh
source "$ROOT/scripts/helpers.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

SESSION="$(ensure_session_for_path "$TMPDIR/my.project")"
[ "$SESSION" = "my_project" ] || fail "expected sanitized session name my_project, got $SESSION"
tmux has-session -t "=$SESSION" 2>/dev/null || fail "created session exists"
[ "$(session_root "$SESSION")" = "$TMPDIR/my.project" ] || fail "session root is recorded"
[ "$(ensure_session_for_path "$TMPDIR/my.project")" = "$SESSION" ] || fail "ensure reuses existing session"

printf 'ok - tmux smoke\n'
