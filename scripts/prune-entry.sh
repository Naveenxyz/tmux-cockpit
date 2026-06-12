#!/usr/bin/env bash
# Remove a directory entry (D:<path>) from the zoxide database — used by the
# ctrl-d binding in the picker to keep the project list clean. Session
# entries (S:) are ignored: killing sessions is ctrl-x's job.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

[ -n "$1" ] || exit 0
parse_target "$1"

[ "$TARGET_KIND" = "dir" ] || exit 0
command -v zoxide >/dev/null 2>&1 || exit 0

zoxide remove "$TARGET_VALUE" 2>/dev/null
exit 0
