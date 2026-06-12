#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-project-list.XXXXXX")"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT HUP INT TERM

mkdir -p "$TMPDIR/bin" "$TMPDIR/home/proj" "$TMPDIR/home-other/proj" \
  "$TMPDIR/static/alpha" "$TMPDIR/static/beta" "$TMPDIR/other"

cat >"$TMPDIR/bin/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    if [ "$2" = "-p" ]; then
      printf '%s\n' "${COCKPIT_TEST_CURRENT_SESSION:-api}"
      exit 0
    fi
    exit 0
    ;;
  list-sessions)
    printf 'api\t%s\t%s\n' "$COCKPIT_TEST_HOME/proj" "$COCKPIT_TEST_HOME/proj"
    printf 'other\t%s\t\n' "$COCKPIT_TEST_TMP/other"
    exit 0
    ;;
  show-option)
    if [ "$3" = "@cockpit-project-dirs" ]; then
      printf '%s\n' "$COCKPIT_TEST_STATIC"
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMPDIR/bin/tmux"

cat >"$TMPDIR/bin/zoxide" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "query" ] && [ "$2" = "-l" ]; then
  printf '%s\n' \
    "$COCKPIT_TEST_HOME/proj" \
    "$COCKPIT_TEST_TMP/home-other/proj" \
    "$COCKPIT_TEST_STATIC/alpha"
  exit 0
fi
exit 1
STUB
chmod +x "$TMPDIR/bin/zoxide"

export COCKPIT_TEST_TMP="$TMPDIR"
export COCKPIT_TEST_HOME="$TMPDIR/home"
export COCKPIT_TEST_STATIC="$TMPDIR/static"
export COCKPIT_TEST_CURRENT_SESSION="api"
export HOME="$TMPDIR/home"

out="$(PATH="$TMPDIR/bin:$PATH" "$ROOT/scripts/project-list.sh")"

fail() {
  printf 'not ok - %s\nOutput:\n%s\n' "$1" "$out" >&2
  exit 1
}

count_target() {
  printf '%s\n' "$out" | awk -F '\t' -v target="$1" '$1 == target { count++ } END { print count + 0 }'
}

[ "$(count_target "S:api")" = "1" ] || fail "open session is listed once"
[ "$(count_target "D:$TMPDIR/home/proj")" = "0" ] || fail "zoxide duplicate of open session is suppressed"
[ "$(count_target "D:$TMPDIR/home-other/proj")" = "1" ] || fail "home-prefix sibling path is kept"
[ "$(count_target "D:$TMPDIR/static/alpha")" = "1" ] || fail "zoxide static child is listed"
[ "$(count_target "D:$TMPDIR/static/beta")" = "1" ] || fail "static-only child is listed"
[ "$(count_target "D:$TMPDIR/static/alpha")" = "1" ] || fail "static child already seen through zoxide is not duplicated"

case "$out" in
  *'~-other'*) fail "display_path overmatched HOME prefix" ;;
esac

printf 'ok - project-list\n'
