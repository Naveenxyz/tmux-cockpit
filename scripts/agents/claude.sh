#!/usr/bin/env bash
# Agent module: Claude Code (https://claude.com/claude-code)
#
# Agent modules are sourced by agent-list.sh (and the tests). Each module
# named <name>.sh defines:
#   <name>_procs   space-separated process names (comm basenames) that
#                  identify this agent inside a pane's process tree
# Keep modules bash-3.2 compatible and side-effect free.

# The launcher renames itself to the version number ("2.1.175"), but the
# actual agent process is always comm "claude".
# Read via eval by agent-list.sh.
# shellcheck disable=SC2034
claude_procs="claude"
