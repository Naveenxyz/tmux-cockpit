# tmux-cockpit

Use tmux as your AI coding app. One session per project and a fuzzy project
switcher powered by your [zoxide](https://github.com/ajeetdsouza/zoxide)
history — like the Claude or Codex desktop apps, but in tmux. Out of the box
new sessions are plain tmux; set `@cockpit-auto-commands` to have your AI
CLIs (or anything else) already running in their own windows in the project
directory.

## What you get

- **`prefix + o`** — popup project picker. Fuzzy-search your zoxide history
  and open sessions, with a preview showing session windows, git status, and
  a file tree. Pick a directory and it becomes (or switches to) a session.
  The first nine entries are numbered: press `1`-`9` to open one instantly
  (digits jump, they're never typed into the query). `ctrl-x` kills a
  session (attached sessions are protected).
- **Session-per-project** — sessions are named after the directory, created
  on demand, and reused on the next visit. Same-named projects in different
  paths get unique names automatically.
- **Auto commands** — with `@cockpit-auto-commands` set (e.g.
  `claude:claude;pi:pi`), every new session opens one window per entry,
  named and running its command in the project root, plus an extra
  plain-shell window (auto-named by tmux). Unset (the default), new sessions are a single plain
  window — the standard tmux experience.
- **`cockpit` CLI (the `zt` workflow)** — works from any terminal, inside
  or outside tmux (it starts the server if needed):
  - `cockpit` — open the fuzzy picker
  - `cockpit .` — session for the current directory
  - `cockpit path/to/dir` — session for a directory
  - `cockpit api` — session for the best zoxide match for "api"

## Requirements

- tmux ≥ 3.2 (for `display-popup`)
- [fzf](https://github.com/junegunn/fzf)
- [zoxide](https://github.com/ajeetdsouza/zoxide) (recommended — it supplies
  the project list; without it, set `@cockpit-project-dirs`)
- Optional: `eza` or `tree` for nicer previews

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'Naveenxyz/tmux-cockpit'
```

Then press `prefix + I`. That's it — no scripts to copy, no shell config to
edit.

Manual install:

```sh
git clone https://github.com/Naveenxyz/tmux-cockpit ~/.tmux/plugins/tmux-cockpit
```

```tmux
# ~/.tmux.conf
run-shell ~/.tmux/plugins/tmux-cockpit/cockpit.tmux
```

Optional CLI — symlink `bin/cockpit` somewhere on your `PATH`, under any
name you like (`zt` is a nice short one):

```sh
ln -s ~/.tmux/plugins/tmux-cockpit/bin/cockpit /usr/local/bin/cockpit
ln -s ~/.tmux/plugins/tmux-cockpit/bin/cockpit /usr/local/bin/zt
```

Then `zt .`, `zt myproject`, or plain `zt` from any terminal — tmux running
or not.

## Configuration

All options are optional; set them in `~/.tmux.conf` before the plugin line.

```tmux
# Keys
set -g @cockpit-popup-key 'o'            # prefix + key for the popup picker

# Auto commands for new project sessions (default: unset — plain tmux).
# Format: command:name;command:name  — one window per entry, plus a final
# plain-shell window. The name is optional (defaults to the command's first
# word). Quote a command with '' or "" if it contains ':' or ';'.
set -g @cockpit-auto-commands 'claude:claude;pi:pi'

# Popup size and looks
set -g @cockpit-popup-width '75%'
set -g @cockpit-popup-height '65%'
set -g @cockpit-popup-title ' projects '
# Extra fzf flags for the picker, e.g. a --color theme (FZF_DEFAULT_OPTS
# doesn't reach tmux popups, so theme the picker here instead)
set -g @cockpit-fzf-opts '--color=bg+:#283457,hl:#7aa2f7'

# Extra project sources (colon-separated; each dir's children are offered).
# Useful without zoxide, or for dirs you haven't visited yet.
set -g @cockpit-project-dirs '~/projects:~/work'
```

Example — Claude, a dev server with a custom name, and Codex, each in their
own window of every new project session:

```tmux
set -g @cockpit-auto-commands 'claude;"npm run dev":dev;codex'
```

## How it works

- `scripts/project-list.sh` merges open tmux sessions with `zoxide query -l`
  (deduped by path, frecency order).
- `scripts/open-project.sh` resolves a directory to a session name
  (basename, sanitized; suffixed on collisions, tracked via the
  `@cockpit-root` session option), creates the session if needed (one
  window per `@cockpit-auto-commands` entry plus a plain shell), bumps zoxide,
  and switches/attaches.

## Known limitations

- **Same-name sessions you created by hand are trusted.** Opening
  `~/work/api` when an unrelated session named `api` already exists
  attaches to that session rather than creating a duplicate. Sessions
  created through cockpit record their root and are disambiguated
  (`api`, `api-2`, ...).
- Keys and popup size are read when the plugin loads; changing them
  requires a tmux config reload. All other options apply live.

## License

MIT
