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
# makes, and is driven by env vars (WIN_NAME, MARKED, WINS, ROOT_OPT).
cat >"$TMPDIR/bin/tmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$LOG"
case "$1" in
  display-message)
    fmt=""
    for a in "$@"; do case "$a" in '#{'*) fmt="$a" ;; esac; done
    case "$fmt" in
      '#{session_name}') echo "proj" ;;
      '#{window_id}') echo "@1" ;;
      '#{window_name}') echo "${WIN_NAME:-bash}" ;;
      '#{pane_current_path}') echo "${HOME}" ;;
      *) echo "" ;;
    esac ;;
  show-options | show-option)
    case "$*" in
      *@cockpit-nvim-window*) echo "${MARKED:-}" ;;
      *@cockpit-nvim-command*) echo "${NVIM_CMD:-}" ;;
      *@cockpit-nvim-name*) echo "" ;;
      *@cockpit-root*) echo "${ROOT_OPT:-}" ;;
      *) echo "" ;;
    esac ;;
  list-windows) printf '%b' "${WINS:-}" ;;
  new-window) echo "@9" ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$TMPDIR/bin/tmux"

fail() { printf 'not ok - %s\n  log:\n%s\n' "$1" "$(cat "$LOG" 2>/dev/null)" >&2; exit 1; }
run() { : >"$LOG"; PATH="$TMPDIR/bin:$PATH" TMUX="fake" "$ROOT/scripts/nvim-toggle.sh"; }
logged() { grep -q "$1" "$LOG"; }

# --- in the editor window (tagged) -> go back to the previous window ----
MARKED=1 WIN_NAME=bash run >/dev/null 2>&1 || fail "toggle-back exited non-zero"
logged "last-window -t proj" || fail "expected 'last-window' when in the nvim window"

# --- in the editor window (detected by name) -> go back -----------------
MARKED="" WIN_NAME=nvim run >/dev/null 2>&1 || fail "toggle-back (by name) failed"
logged "last-window -t proj" || fail "expected 'last-window' when window name is nvim"

# --- a normal window with an existing nvim window -> switch to it -------
MARKED="" WIN_NAME=bash WINS=$'@1\t\tbash\n@4\t1\tnvim\n' run >/dev/null 2>&1 \
  || fail "switch-existing failed"
logged "select-window -t @4" || fail "expected switch to existing nvim window @4"
if logged "new-window"; then fail "should not create a window when one exists"; fi

# --- a normal window, no nvim window -> create one at the project root --
ROOT_OPT="$HOME" MARKED="" WIN_NAME=bash WINS=$'@1\t\tbash\n' run >/dev/null 2>&1 \
  || fail "create-window failed"
logged "new-window" || fail "expected new-window to create the nvim window"
logged "@cockpit-nvim-window 1" || fail "new window should be tagged"
logged "automatic-rename off" || fail "new window should keep a stable name"

printf 'ok - nvim\n'
