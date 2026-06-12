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
cols="${FZF_PREVIEW_COLUMNS:-80}"

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

  # The pane's visible screen, colors preserved, reframed for the
  # preview window:
  #  - Squeeze runs of blank lines to one (ignoring color codes when
  #    judging blankness): agent TUIs anchor with large blank regions
  #    (pi pins its footer to the pane bottom, codex leaves everything
  #    below its content empty) that would push the conversation out
  #    of frame.
  #  - Lines wider than the preview get their interior space-gaps
  #    squeezed (preserving indentation), so right-aligned footer text
  #    (e.g. pi's model/stats) is pulled back into view instead of
  #    being truncated off-screen. Fitting lines pass through intact.
  tmux capture-pane -ep -t "$pane" 2>/dev/null \
    | awk -v esc="$(printf '\033')" -v cols="$cols" '
        {
          plain = $0
          gsub(esc "\\[[0-9;]*m", "", plain)
          if (plain ~ /^[[:space:]]*$/) { if (started) pending = 1; next }
          if (pending) { print ""; pending = 0 }
          started = 1
          if (length(plain) > cols) {
            match($0, /^ */)
            indent = substr($0, 1, RLENGTH)
            rest = substr($0, RLENGTH + 1)
            gsub(/   +/, "  ", rest)
            print indent rest
          } else {
            print
          }
        }
      ' \
    | tail -n "$((lines - 4))"

  sleep 1
done
