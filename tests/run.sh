#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in "$ROOT"/cockpit.tmux "$ROOT"/bin/cockpit "$ROOT"/scripts/*.sh \
  "$ROOT"/scripts/lib/*.sh "$ROOT"/scripts/agents/*.sh "$ROOT"/tests/*.sh; do
  bash -n "$file"
done

"$ROOT/tests/test-helpers.sh"
"$ROOT/tests/test-agents.sh"
"$ROOT/tests/test-project-list.sh"
"$ROOT/tests/test-feature.sh"
"$ROOT/tests/test-tmux-smoke.sh"

printf 'ok - all tests\n'
