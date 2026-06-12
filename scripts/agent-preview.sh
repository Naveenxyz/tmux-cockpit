#!/usr/bin/env bash
# fzf preview for the agent picker: where the pane lives, then its live
# screen (colors preserved via capture-pane -e), redrawn every second.
#
# The loop never exits on its own — fzf kills the preview process when
# the selection changes or the picker closes. Each frame clears the
# preview with ESC[2J (fzf supports the clear-screen sequence exactly so
# previews can act like `watch`).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

target="$1"
case "$target" in
  A:*) pane="${target#A:}" ;;
  *) exit 0 ;;
esac

lines="${FZF_PREVIEW_LINES:-40}"

while :; do
  info="$(tmux display-message -p -t "$pane" \
    $'#{session_name} · #{window_index}:#{window_name}\t#{pane_current_path}' 2>/dev/null)"
  if [ -z "$info" ]; then
    printf '\033[2J\033[H\npane is gone — ctrl-r to refresh the list\n'
    exit 0
  fi

  printf '\033[2J\033[H'
  printf '\033[1m%s\033[0m\n\033[2m%s\033[0m\n\n' \
    "${info%%$'\t'*}" "$(display_path "${info#*$'\t'}")"

  # The pane's visible screen, colors preserved. Agent TUIs anchor with
  # large blank regions (pi pins its footer to the bottom of the pane,
  # codex leaves everything below its content empty), which would fill
  # the preview with blank rows and push the conversation out of frame.
  # Squeeze runs of blank lines to one (ignoring color codes when judging
  # blankness), then bottom-align what's left.
  tmux capture-pane -ep -t "$pane" 2>/dev/null \
    | awk -v esc="$(printf '\033')" '
        {
          plain = $0
          gsub(esc "\\[[0-9;]*m", "", plain)
          if (plain ~ /^[[:space:]]*$/) { if (started) pending = 1; next }
          if (pending) { print ""; pending = 0 }
          started = 1
          print
        }
      ' \
    | tail -n "$((lines - 4))"

  sleep 1
done
