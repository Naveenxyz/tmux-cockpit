# tmux-cockpit

Use tmux as your AI coding cockpit: one session per project, fast project
switching, agent-pane discovery, git worktree creation, scratch terminals, and
lazygit popups.

## Features

### Project picker — `prefix + o`

Open the project popup from tmux:

- fuzzy-search open tmux sessions and zoxide history
- press `1`-`9` to open the first nine entries immediately
- type a real path like `~/Desktop/app`, `../repo`, or `work/api` and press
  enter to open it even if zoxide has never seen it
- `ctrl-w` opens the git worktree picker for the selected repo
- `ctrl-f` starts a multi-repo **feature** (see below)
- `ctrl-x` kills the selected detached session
- `ctrl-d` prunes a directory from zoxide history

### Session-per-project

Cockpit names sessions after project directories and records each cockpit-owned
session's root with `@cockpit-root`.

When names collide, cockpit prefers readable parent context before numeric
suffixes:

```text
~/work/api      -> api
~/personal/api  -> personal/api
```

Worktrees under `@cockpit-worktrees-dir` are named with repo context first:

```text
~/worktrees/tmux-cockpit/fix-popup -> tmux-cockpit/fix-popup
```

### Git worktrees

From the project picker, press `ctrl-w` on any git repo to view its worktrees or
create a new one.

The create flow asks for:

1. a branch/worktree name — type a new branch or pick an existing one
2. a location — default is under `@cockpit-worktrees-dir`

Default paths are grouped by repo and protected by a repo marker/hash, so the
same branch name in multiple repos cannot collide silently.

You can also use worktrees from the CLI:

```sh
cockpit -w                         # worktree picker for the current repo
cockpit . -w                       # same, explicitly for current dir
cockpit tmux-cockpit -w            # picker after resolving query/path
cockpit . -w fix-agent-popup       # open existing worktree or create it
cockpit api -w review/readme       # resolve api with zoxide, then create/open
cockpit . -w fix --path ~/tmp/fix  # custom destination
```

If a worktree for the requested branch already exists, cockpit switches to it.
If not, cockpit creates it and opens it as a normal project session.

### Multi-repo features — `ctrl-f`

Work that spans several repos at once (a "feature") gets its own set of
worktrees under `@cockpit-worktrees-dir/features/<name>`.

From the project picker, press `ctrl-f`:

1. **name the feature first** — the current picker query is used as the name,
   or you are prompted for one.
2. **select repos** — a list of directories that contain a `.git` entry. This
   is a multi-select: press `TAB` to mark each repo you want (a `✓` appears),
   `ctrl-a` to mark all, then `enter` to clone them. A plain `enter` with
   nothing marked just uses the highlighted repo.

Clone progress is shown live, one repo at a time, so you can watch each fetch.
If `@cockpit-worktrees-dir/features/<name>` already exists, cockpit
**recreates** it — the existing folder and any cockpit sessions rooted in it
are removed first (after a short warning), then everything is rebuilt.

Cockpit then creates:

```text
~/worktrees/features/<name>/
  repo-a/      # fresh clone of repo-a, on a new branch <name>
  repo-b/      # fresh clone of repo-b, on a new branch <name>
```

By default each repo is **cloned fresh** (from its `origin` remote when it has
one, else from the local repo) and a new branch `<name>` is created from the
clone's default branch — independent, pushable repos. Set
`@cockpit-feature-mode worktree` to instead add a lightweight git **worktree**
per repo (shares the source repo's object store, no clone).

The folder is named after the repo; repos that share a basename are
disambiguated (`repo`, `repo-2`). Pressing `enter` opens the `features/<name>`
folder as a new session.

**Local, often-gitignored files** are copied from each source repo into its
new copy, preserving relative paths — so the projects are ready to run and to
hand to an agent. Copied: `.env` / `.env.*`, `AGENTS.md`, and `CLAUDE.md`
(any depth, skipping `.git` and `node_modules`). Symlinked matches (e.g. a
`CLAUDE.md -> AGENTS.md` link) are dereferenced so the copy is self-contained.

You can also drive features from the CLI:

```sh
cockpit -f                         # picker: name it, then select repos
cockpit -f checkout-flow           # picker with the name pre-filled
cockpit -f checkout-flow api web   # create it from resolved repos directly
```

> Note: terminals can't represent `ctrl-shift-w` (control keys carry no shift
> bit, and `ctrl-w` is already the single-repo worktree key), so this is bound
> to `ctrl-f` ("feature"). Rebind it by editing the `ctrl-f` line in
> `scripts/picker.sh`.

### Manage worktrees & features — `prefix + O`

One place to see and clean up everything cockpit has created under
`@cockpit-worktrees-dir`:

- every git worktree (grouped by repo) and every multi-repo feature
- `enter` / `1`-`9` / click — open the entry as a project session
- `ctrl-x` — **prune** the selected worktree or feature

Pruning is the proper teardown, not a blind `rm`:

- **worktrees** — kills the worktree's cockpit sessions, runs
  `git worktree remove` (so the source repo is left consistent), prunes any
  stale registration, and removes the now-empty repo group folder. If the
  worktree has uncommitted changes git refuses; you are then asked to
  force-remove (which discards them).
- **features** — kills the feature's sessions, and for `worktree`-mode
  features deregisters each repo from its source (`git worktree remove` +
  `git worktree prune`) before deleting the folder, so no dangling worktrees
  are left behind. Clone-mode features are independent and simply removed.

Pruning always asks for confirmation first, and refuses while a session
rooted in the target is still **attached** — detach it first.

```sh
cockpit -W                         # open the manage picker
cockpit . -w --rm fix-popup        # prune one worktree of the current repo
cockpit api -w --rm review/readme  # resolve api, then prune that worktree
cockpit -f --rm checkout-flow      # prune a whole feature
cockpit -f --rm checkout-flow -y   # ...without the confirmation prompt
```

### Agent picker — `prefix + a`

List AI-agent panes across all sessions with live previews:

- `prefix + a` — all sessions
- `prefix + A` — current session only
- `enter` / `1`-`9` — jump to a pane
- `ctrl-r` — reload the list

Built-in detector modules cover Claude Code, Codex, OpenCode, and pi. Detection
is observational via process trees: no agent hooks or config required. Add more
modules under `scripts/agents/` and include them in `@cockpit-agents`.

### Scratch terminal — `prefix + t`

A persistent popup terminal backed by its own tmux session. Close and reopen it
without losing the shell.

### lazygit popup — `prefix + g`

Open lazygit at the git root of the current pane.

### Editor toggle — `prefix + v`

A dedicated nvim window that toggles in and out:

- from any other window, `prefix + v` switches to this session's `nvim` window
  — creating it (running `nvim .` at the project root) if there isn't one yet
- from the nvim window, `prefix + v` jumps back to the window you came from

You always have one nvim window per session, and "go back" rides on tmux's own
last-window tracking. Disable with `@cockpit-nvim off`.

### Auto commands for new sessions

Set `@cockpit-auto-commands` to start AI CLIs or other commands in every new
project session:

```tmux
set -g @cockpit-auto-commands 'claude:claude;pi:pi'
```

Each entry opens in its own named window, plus one extra plain shell window.
Unset by default, new sessions are plain tmux.

## CLI

`cockpit` works inside or outside tmux. Outside tmux it starts/attaches to the
server when needed.

```text
tmux-cockpit

Usage:
  cockpit                         Open the project picker
  cockpit .                       Open current directory as a project session
  cockpit <path>                  Open a path as a project session
  cockpit <query...>              Open best zoxide match as a project session
  cockpit -                       Switch to the previous tmux session

Worktrees:
  cockpit -w                      Worktree picker for the current repo
  cockpit . -w                    Worktree picker for the current repo
  cockpit <query> -w              Worktree picker for a zoxide/path repo
  cockpit . -w <branch>           Open existing worktree for branch, or create it
  cockpit <query> -w <branch>     Same, after resolving query/path to a repo
  cockpit . -w <branch> --path <dir>
                                  Create at a custom path if it does not exist
  cockpit . -w --rm <branch>      Prune the worktree for <branch>
  cockpit <query> -w --rm <branch>   Same, after resolving query/path to a repo

Features (multi-repo):
  cockpit -f                      Feature picker (name it, then select repos)
  cockpit -f <name>               Feature picker with the name pre-filled
  cockpit -f <name> <repo>...     Create feature <name> from the given repos
                                  (each <repo> is a path or a zoxide query)
  cockpit -f --rm <name>          Prune feature <name>

Manage:
  cockpit -W                      Manage picker: list/open/prune worktrees
                                  and features (prefix + O in tmux)

Options:
  -w, --worktree                  Use git worktree mode
  -f, --feature                   Use multi-repo feature mode
  -W, --manage                    Open the manage picker
  --rm                            Prune the selected worktree/feature
  -y, --yes                       Skip the prune confirmation prompt
  --path <dir>                    Custom worktree destination for -w <branch>
  -h, --help                      Show this help
```

Run:

```sh
cockpit --help
```

## Requirements

- tmux ≥ 3.2 for `display-popup`
- [fzf](https://github.com/junegunn/fzf)
- [zoxide](https://github.com/ajeetdsouza/zoxide) recommended for project history
- git for worktree features
- optional: `eza` or `tree` for nicer previews
- optional: `lazygit` for `prefix + g`

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'Naveenxyz/tmux-cockpit'
```

Then press `prefix + I`.

Manual install:

```sh
git clone https://github.com/Naveenxyz/tmux-cockpit ~/.tmux/plugins/tmux-cockpit
```

```tmux
run-shell ~/.tmux/plugins/tmux-cockpit/cockpit.tmux
```

Optional CLI symlink:

```sh
ln -s ~/.tmux/plugins/tmux-cockpit/bin/cockpit /usr/local/bin/cockpit
```

## Configuration

All options are optional. Set them before the plugin line.

```tmux
# Project picker
set -g @cockpit-popup-key 'o'
set -g @cockpit-popup-width '75%'
set -g @cockpit-popup-height '65%'
set -g @cockpit-popup-title ' projects '
set -g @cockpit-fzf-opts '--color=bg+:#283457,hl:#7aa2f7'
set -g @cockpit-project-dirs '~/projects:~/work'

# Previous session key (off by default)
set -g @cockpit-last-key 'p'

# Agent picker
set -g @cockpit-agents-popup 'on'
set -g @cockpit-agents-key 'a'
set -g @cockpit-agents-current-key 'A'
set -g @cockpit-agents 'claude codex opencode pi'
set -g @cockpit-agents-width '75%'
set -g @cockpit-agents-height '65%'

# Worktrees
set -g @cockpit-worktrees-dir '~/worktrees'

# Manage picker (list/prune worktrees and features)
set -g @cockpit-manage-key 'O'

# Multi-repo features (ctrl-f in the project picker)
# 'clone' (default): fresh clone per repo, new branch from main
# 'worktree': lightweight git worktree per repo
set -g @cockpit-feature-mode 'clone'

# Scratch terminal
set -g @cockpit-scratch 'on'
set -g @cockpit-scratch-key 't'
set -g @cockpit-scratch-dir '~'
set -g @cockpit-scratch-session 'scratch'
set -g @cockpit-scratch-width '80%'
set -g @cockpit-scratch-height '80%'

# lazygit
set -g @cockpit-lazygit 'on'
set -g @cockpit-lazygit-key 'g'
set -g @cockpit-lazygit-width '90%'
set -g @cockpit-lazygit-height '90%'

# Editor toggle window (prefix + v)
set -g @cockpit-nvim 'on'
set -g @cockpit-nvim-key 'v'
set -g @cockpit-nvim-command 'nvim .'
set -g @cockpit-nvim-name 'nvim'

# Auto commands for new project sessions
set -g @cockpit-auto-commands 'claude:claude;pi:pi'
```

## How it works

- `scripts/project-list.sh` merges open tmux sessions with `zoxide query -l`
  and optional static roots from `@cockpit-project-dirs`.
- `scripts/open-project.sh` creates or reuses a session for a directory, stores
  `@cockpit-root`, bumps zoxide, and switches/attaches.
- `scripts/worktree-picker.sh` and `scripts/open-worktree.sh` list, create, and
  open git worktrees using the same project-session machinery.
- `scripts/repo-list.sh`, `scripts/feature-picker.sh`, and
  `scripts/open-feature.sh` drive multi-repo features: pick git repos, then
  clone (or worktree) each under `features/<name>` and copy in `.env` files.
- `scripts/manage-list.sh`, `scripts/manage-picker.sh`, and
  `scripts/prune.sh` power the manage picker: list every worktree/feature
  under the worktrees dir, and prune one by killing its sessions and running
  the right git teardown (`git worktree remove`/`prune`) before deleting it.
- `scripts/agent-list.sh` finds agent panes by walking pane process trees from a
  single `ps` snapshot.
- `scripts/helpers.sh` is a thin loader for `scripts/lib/` — `util.sh` (options,
  paths, messaging), `session.sh` (session naming and lifecycle), and
  `worktree.sh` (git/worktree paths). Every script sources `helpers.sh`.

## Development

Run local checks:

```sh
tests/run.sh
shellcheck -e SC1090,SC1091 cockpit.tmux bin/cockpit scripts/*.sh scripts/lib/*.sh scripts/agents/*.sh tests/*.sh
```

CI runs two jobs: a Linux job (ShellCheck + the suite) and a macOS job that
runs the suite under the system **bash 3.2**, so the bash-3.2 compatibility the
scripts rely on is actually verified.

To reproduce the bash-3.2 run locally on macOS:

```sh
shim="$(mktemp -d)"; ln -sf /bin/bash "$shim/bash"
PATH="$shim:$PATH" tests/run.sh   # #!/usr/bin/env bash now resolves to 3.2
```

## Known limitations

- Same-name sessions created manually are trusted. If a manual session named
  `api` exists, opening `~/work/api` attaches to it rather than creating a
  duplicate.
- Keys and popup size are read when the plugin loads; changing them requires a
  tmux config reload. Most other options apply live.
- The manage picker (`prefix + O`) lists worktrees and features under
  `@cockpit-worktrees-dir`. Worktrees created with a custom `-w --path`
  outside that directory are not tracked there, so they are not listed; remove
  them with `cockpit <repo> -w --rm <branch>` or plain `git worktree remove`.

## License

MIT
