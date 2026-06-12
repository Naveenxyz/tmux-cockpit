#!/usr/bin/env bash
# lazygit in a popup (prefix + g), opened at the git root of the current
# pane's directory (falls back to the pane directory outside a repo).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

require_cmd lazygit "install it (brew install lazygit) to use the git popup"

dir="$(tmux display-message -p '#{pane_current_path}')"
dir="${dir:-$HOME}"

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
dir="${root:-$dir}"

width="$(get_opt "@cockpit-lazygit-width" "90%")"
height="$(get_opt "@cockpit-lazygit-height" "90%")"

exec tmux display-popup -d "$dir" -w "$width" -h "$height" -E lazygit
