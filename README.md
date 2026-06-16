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
  (digits jump, they're never typed into the query). Type a real path
  (`~/Desktop/app`, `../repo`, `work/api`) and press enter to open it even
  if zoxide has never seen it. `ctrl-w` opens the git worktree picker for
  the selected repo, `ctrl-x` kills a session (attached sessions are
  protected), and `ctrl-d` prunes a directory from zoxide's history,
  keeping the list clean.
- **Session-per-project** — sessions are named after the directory, created
  on demand, and reused on the next visit. Same-named projects in different
  paths get unique names automatically.
- **Auto commands** — with `@cockpit-auto-commands` set (e.g.
  `claude:claude;pi:pi`), every new session opens one window per entry,
  named and running its command in the project root, plus an extra
  plain-shell window (auto-named by tmux). Unset (the default), new sessions are a single plain
  window — the standard tmux experience.
- **`prefix + a`** — agent popup. Every AI-agent pane across all your
  sessions in one list, ordered by project — Claude Code, Codex,
  OpenCode, and pi out of the box. The preview is the selected pane's
  live screen, auto-refreshing every second, so you can watch an agent
  work without leaving the popup. `enter`/`1`-`9` jumps straight to the
  pane, `ctrl-r` reloads the list. `prefix + A` is the same picker
  scoped to the current session. Detection is purely observational
  (process tree) — no agent-side hooks or config to install. Agents are
  pluggable: drop a module in `scripts/agents/` (see `agents/claude.sh`)
  and add its name to `@cockpit-agents`.
- **`prefix + t`** — scratch terminal in a popup, backed by a persistent
  session (close and reopen, your shell is still there). Starts in `$HOME`
  by default; press the key again inside to close.
- **`prefix + g`** — [lazygit](https://github.com/jesseduffield/lazygit) in
  a popup, opened at the git root of whatever directory the current pane is
  in. (Requires lazygit; the binding just won't do anything without it.)
- **`cockpit` CLI (the `zt` workflow)** — works from any terminal, inside
  or outside tmux (it starts the server if needed):
  - `cockpit` — open the fuzzy picker
  - `cockpit .` — session for the current directory
  - `cockpit -` — back to the previous session, like `cd -`
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
set -g @cockpit-last-key ''              # prefix + key for previous session
                                         # (off by default — e.g. 'p' collides
                                         # with stock previous-window)

# Agent popup (prefix + a all sessions, prefix + A current session)
set -g @cockpit-agents-popup 'on'        # 'off' to disable the bindings
set -g @cockpit-agents-key 'a'
set -g @cockpit-agents-current-key 'A'
set -g @cockpit-agents 'claude codex opencode pi'  # modules to load from scripts/agents/
set -g @cockpit-agents-width '75%'       # defaults to @cockpit-popup-width
set -g @cockpit-agents-height '65%'      # defaults to @cockpit-popup-height

# Scratch terminal popup (prefix + t)
set -g @cockpit-scratch 'on'             # 'off' to disable the binding
set -g @cockpit-scratch-key 't'
set -g @cockpit-scratch-dir '~'          # start directory
set -g @cockpit-scratch-session 'scratch' # backing session name
set -g @cockpit-scratch-width '80%'
set -g @cockpit-scratch-height '80%'

# lazygit popup at the current repo root (prefix + g)
set -g @cockpit-lazygit 'on'             # 'off' to disable the binding
set -g @cockpit-lazygit-key 'g'
set -g @cockpit-lazygit-width '90%'
set -g @cockpit-lazygit-height '90%'

# Git worktrees (from the project picker: ctrl-w)
set -g @cockpit-worktrees-dir '~/worktrees' # default create location

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
- `scripts/open-project.sh` resolves a directory to a readable session name
  (basename first, then parent/name, grandparent/parent/name, and only then
  numeric suffixes), tracked via the `@cockpit-root` session option. It
  creates the session if needed (one window per `@cockpit-auto-commands`
  entry plus a plain shell), bumps zoxide, and switches/attaches.
- `scripts/worktree-picker.sh` lists `git worktree list` for the selected
  repo and can create a new worktree under `@cockpit-worktrees-dir`. Default
  paths are grouped by repo name and protected by a repo marker/hash so the
  same branch name in multiple repos cannot collide silently. Sessions for
  paths under the worktrees directory are named with repo context first
  (`repo/branch`) rather than just `branch`.
- `scripts/agent-list.sh` finds agent panes by walking each pane's process
  tree (one `ps` snapshot, one awk pass — `#{pane_current_command}` lies:
  Claude's launcher renames itself, pi shows up as `node`). A
  `scripts/agents/<name>.sh` module is one definition: `<name>_procs`,
  the process names that claim a pane for that agent. The picker's
  preview loops `capture-pane -e` once a second, clearing with `ESC[2J`
  (fzf renders that as a watch-style live preview).

## Development

Run the local checks with:

```sh
tests/run.sh
```

The test suite covers the auto-command parser, session-name collision
resolution, project-list deduping, the agent module interface, and a
small isolated tmux smoke test. CI also runs `bash -n` and ShellCheck.

## Known limitations

- **Same-name sessions you created by hand are trusted.** Opening
  `~/work/api` when an unrelated session named `api` already exists
  attaches to that session rather than creating a duplicate. Sessions
  created through cockpit record their root and are disambiguated with
  parent context when possible (`api`, `work/api`, ...).
- Keys and popup size are read when the plugin loads; changing them
  requires a tmux config reload. All other options apply live.

## License

MIT
