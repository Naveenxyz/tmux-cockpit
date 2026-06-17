#!/usr/bin/env bash
# Shared helpers for tmux-cockpit. Sourced by every script.
#
# This is a thin loader: the implementation lives in lib/ modules, split by
# concern so each file stays small and focused.
#   lib/util.sh     — options, path/home handling, messaging, fzf-entry parsing
#   lib/session.sh  — session naming, resolution, and lifecycle
#   lib/worktree.sh — git repo / worktree path helpers
# Order matters: session.sh and worktree.sh call into util.sh helpers.

# Used by scripts that source helpers.sh.
# shellcheck disable=SC2034
COCKPIT_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COCKPIT_LIB="$COCKPIT_SCRIPTS/lib"

# shellcheck source=lib/util.sh
source "$COCKPIT_LIB/util.sh"
# shellcheck source=lib/session.sh
source "$COCKPIT_LIB/session.sh"
# shellcheck source=lib/worktree.sh
source "$COCKPIT_LIB/worktree.sh"
