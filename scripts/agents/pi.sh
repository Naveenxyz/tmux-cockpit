#!/usr/bin/env bash
# Agent module: pi (https://github.com/badlogic/pi-mono)
# See agents/claude.sh for the module interface.

# pi runs as a node script whose process comm is "pi".
# Read via eval by agent-list.sh.
# shellcheck disable=SC2034
pi_procs="pi"
