#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-nvim.XXXXXX")"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT HUP INT TERM

export HOME="$TMPDIR/home"
mkdir -p "$HOME" "$TMPDIR/bin"
LOG="$TMPDIR/tmux.log"
export LOG
# Use a real, always-present command so require_cmd passes without nvim.
export NVIM_CMD="true ."

# tmux stub: logs every invocation, answers the format queries the script
# makes, and is driven by env vars (CUR_CMD, MARKED, PANES, ROOT_OPT).
cat >"$TMPDIR/bin/tmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG"
case "$1" in
  display-message)
    fmt=""
    for a in "$@"; do case "$a" in '#{'*) fmt="$a" ;; esac; done
    case "$fmt" in
      '#{pane_id}') echo "%5" ;;
      '#{window_id}') echo "@1" ;;
      '#{pane_current_command}') echo "${CUR_CMD:-bash}" ;;
      '#{pane_current_path}') echo "${HOME}" ;;
      '#{session_name}') echo "proj" ;;
      *) echo "" ;;
    esac ;;
  show-options | show-option)
    case "$*" in
      *@cockpit-nvim-pane*) echo "${MARKED:-}" ;;
      *@cockpit-nvim-command*) echo "${NVIM_CMD:-}" ;;
      *@cockpit-root*) echo "${ROOT_OPT:-}" ;;
      *) echo "" ;;
    esac ;;
  list-panes) printf '%b' "${PANES:-}" ;;
  split-window) echo "%9" ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$TMPDIR/bin/tmux"

fail() { printf 'not ok - %s\n  log:\n%s\n' "$1" "$(cat "$LOG" 2>/dev/null)" >&2; exit 1; }
run() { : >"$LOG"; PATH="$TMPDIR/bin:$PATH" TMUX="fake" "$ROOT/scripts/nvim-toggle.sh"; }
logged() { grep -q "$1" "$LOG"; }

# --- in the editor pane (marked) -> go back to the previous pane --------
MARKED=1 CUR_CMD=bash run >/dev/null 2>&1 || fail "toggle-back exited non-zero"
logged "last-pane -t @1" || fail "expected 'last-pane' when in the nvim pane"

# --- in the editor pane (detected by command) -> go back ----------------
MARKED="" CUR_CMD=nvim run >/dev/null 2>&1 || fail "toggle-back (by cmd) failed"
logged "last-pane -t @1" || fail "expected 'last-pane' when current command is nvim"

# --- a normal pane with an existing nvim pane -> focus it ---------------
MARKED="" CUR_CMD=bash PANES=$'%4\t\tbash\n%7\t1\tnvim\n' run >/dev/null 2>&1 \
  || fail "focus-existing failed"
logged "select-pane -t %7" || fail "expected focus of existing nvim pane %7"
if logged "split-window"; then fail "should not split when an nvim pane exists"; fi

# --- a normal pane, no nvim pane -> create one at the project root ------
ROOT_OPT="$HOME" MARKED="" CUR_CMD=bash PANES=$'%4\t\tbash\n' run >/dev/null 2>&1 \
  || fail "create-pane failed"
logged "split-window" || fail "expected split-window to create the nvim pane"
logged "@cockpit-nvim-pane 1" || fail "new pane should be tagged"
logged "select-pane -t %9 -T nvim" || fail "new pane should be titled nvim"

printf 'ok - nvim\n'
