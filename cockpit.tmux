#!/usr/bin/env bash
# tmux-cockpit — project sessions for AI-first tmux workflows.
# This is the TPM entry point; it sets up key bindings. Keys and popup size
# are baked into the bindings here (changing them needs a config reload);
# all other @cockpit-* options are read at runtime.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

get_opt() {
  local value
  value="$(tmux show-option -gqv "$1")"
  printf '%s' "${value:-$2}"
}

popup_key="$(get_opt "@cockpit-popup-key" "o")"
popup_width="$(get_opt "@cockpit-popup-width" "75%")"
popup_height="$(get_opt "@cockpit-popup-height" "65%")"

popup_title="$(get_opt "@cockpit-popup-title" " projects ")"

tmux bind-key "$popup_key" display-popup -w "$popup_width" -h "$popup_height" -T "$popup_title" -E "'$SCRIPTS/picker.sh'"

# Scratch terminal popup (persistent session). Disable: @cockpit-scratch off
if [ "$(get_opt "@cockpit-scratch" "on")" = "on" ]; then
  scratch_key="$(get_opt "@cockpit-scratch-key" "t")"
  tmux bind-key "$scratch_key" run-shell "'$SCRIPTS/scratch-popup.sh'"
fi

# lazygit popup at the current repo root. Disable: @cockpit-lazygit off
if [ "$(get_opt "@cockpit-lazygit" "on")" = "on" ]; then
  lazygit_key="$(get_opt "@cockpit-lazygit-key" "g")"
  tmux bind-key "$lazygit_key" run-shell "'$SCRIPTS/lazygit-popup.sh'"
fi
