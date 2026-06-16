#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/helpers.sh
source "$ROOT/scripts/helpers.sh"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  expected="$1"
  actual="$2"
  desc="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'not ok - %s\n  expected: %s\n  actual:   %s\n' "$desc" "$expected" "$actual" >&2
    exit 1
  fi
}

parse_auto_commands 'claude;"npm run dev":dev;"echo a;b:c":runner;codex'
assert_eq 4 "${#AUTO_CMDS[@]}" "parse_auto_commands command count"
assert_eq "claude" "${AUTO_CMDS[0]}" "command 0"
assert_eq "claude" "${AUTO_NAMES[0]}" "default name 0"
assert_eq "npm run dev" "${AUTO_CMDS[1]}" "quoted command with spaces"
assert_eq "dev" "${AUTO_NAMES[1]}" "explicit name"
assert_eq "echo a;b:c" "${AUTO_CMDS[2]}" "quoted command with separators"
assert_eq "runner" "${AUTO_NAMES[2]}" "explicit name for quoted command"
assert_eq "codex" "${AUTO_CMDS[3]}" "final command"
assert_eq "codex" "${AUTO_NAMES[3]}" "default name final command"

parse_auto_commands '  "foo:bar" : custom ; ; "two words"  '
assert_eq 2 "${#AUTO_CMDS[@]}" "parse_auto_commands skips empty entries"
assert_eq "foo:bar" "${AUTO_CMDS[0]}" "colon inside quoted command"
assert_eq "custom" "${AUTO_NAMES[0]}" "trimmed explicit name"
assert_eq "two words" "${AUTO_CMDS[1]}" "trimmed quoted command"
assert_eq "two" "${AUTO_NAMES[1]}" "default name is first word"

HOME="/tmp/cockpit-home"
assert_eq "~" "$(display_path "/tmp/cockpit-home")" "display_path home"
# Literal tilde expected in the output, not an expansion.
# shellcheck disable=SC2088
assert_eq "~/src" "$(display_path "/tmp/cockpit-home/src")" "display_path child"
assert_eq "/tmp/cockpit-home-other/src" "$(display_path "/tmp/cockpit-home-other/src")" "display_path does not overmatch home prefix"
assert_eq "tmux-cockpit: example error" "$(TMUX='' cockpit_error "example error" 2>&1)" "cockpit_error writes to stderr outside tmux"

assert_eq "my_project" "$(session_name_for "/tmp/my.project")" "session name replaces dots"
assert_eq "my_project" "$(session_name_for "/tmp/my:project")" "session name replaces colons"
assert_eq "my_project" "$(session_name_for "/tmp/my project")" "session name replaces spaces"
assert_eq "root" "$(session_name_for "/")" "session name for filesystem root"
assert_eq $'api\ntmp/api' "$(session_name_candidates_for_path "/tmp/api")" "session candidates add parent context"

session_exists() {
  case "$1" in
    api|api-2|manual) return 0 ;;
    *) return 1 ;;
  esac
}

session_root() {
  case "$1" in
    api) printf '/tmp/other-api' ;;
    api-2) printf '/tmp/api' ;;
    manual) printf '' ;;
  esac
}

assert_eq "tmp/api" "$(resolve_session_for_path "/tmp/api")" "resolve existing cockpit-owned collision with parent context"
assert_eq "api-3" "$(resolve_session_for_path "/tmp/api-3")" "resolve next collision suffix"
assert_eq "manual" "$(resolve_session_for_path "/tmp/manual")" "manual sessions without roots are trusted"

printf 'ok - helpers\n'
