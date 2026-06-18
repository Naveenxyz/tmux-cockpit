#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-prune.XXXXXX")"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT HUP INT TERM

export GIT_AUTHOR_NAME=cockpit-test GIT_AUTHOR_EMAIL=test@cockpit
export GIT_COMMITTER_NAME=cockpit-test GIT_COMMITTER_EMAIL=test@cockpit
export HOME="$TMPDIR/home"
export FEATURE_MODE=""
export COCKPIT_YES=1        # never prompt in tests
mkdir -p "$HOME" "$TMPDIR/bin"

WT="$TMPDIR/worktrees"

mk_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" checkout -q -b main
  : >"$dir/README"
  git -C "$dir" add README
  git -C "$dir" commit -q -m init
}

mk_repo "$TMPDIR/repoA"
mk_repo "$TMPDIR/repoB"

# Minimal tmux stub: no sessions, worktrees-dir + feature-mode from env.
cat >"$TMPDIR/bin/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  show-option)
    for a in "\$@"; do
      [ "\$a" = "@cockpit-worktrees-dir" ] && { printf '%s\n' "$WT"; exit 0; }
      [ "\$a" = "@cockpit-feature-mode" ] && { printf '%s\n' "\$FEATURE_MODE"; exit 0; }
    done
    exit 0 ;;
  list-sessions) exit 0 ;;
  has-session) exit 1 ;;
  new-session) printf '%%0\n'; exit 0 ;;
  display-message) printf '\n'; exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMPDIR/bin/tmux"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
prune() { PATH="$TMPDIR/bin:$PATH" TMUX='' "$ROOT/scripts/prune.sh" "$@"; }
feature() { PATH="$TMPDIR/bin:$PATH" TMUX='' "$ROOT/scripts/open-feature.sh" "$@"; }

# Build a worktree in the cockpit layout: <WT>/<slug>/.cockpit-repo + branch dir.
mk_worktree() {
  local repo="$1" branch="$2" slug group common
  slug="$(basename "$repo")"
  group="$WT/$slug"
  mkdir -p "$group"
  common="$(cd "$repo" && git rev-parse --git-common-dir && cd - >/dev/null)"
  printf '%s\n' "$common" >"$group/.cockpit-repo"
  git -C "$repo" worktree add -q -b "$branch" "$group/$branch" >/dev/null 2>&1
  printf '%s' "$group/$branch"
}

# --- prune a worktree via --worktree <repo> <branch> --------------------
wt="$(mk_worktree "$TMPDIR/repoA" feat-1)"
[ -d "$wt" ] || fail "setup: worktree not created"
prune --worktree "$TMPDIR/repoA" feat-1 >/dev/null 2>&1 \
  || fail "prune --worktree exited non-zero"
[ -e "$wt" ] && fail "worktree dir should be gone after prune"
if git -C "$TMPDIR/repoA" worktree list --porcelain | grep -q "feat-1"; then
  fail "worktree still registered with source repo after prune"
fi
# repo-group folder was empty (only the marker) -> removed entirely.
[ -e "$WT/repoA" ] && fail "empty repo-group folder should be cleaned up"

# --- prune a worktree via the W:<path> target form ----------------------
wt2="$(mk_worktree "$TMPDIR/repoA" feat-2)"
prune "W:$wt2" >/dev/null 2>&1 || fail "prune W:<path> exited non-zero"
[ -e "$wt2" ] && fail "worktree dir should be gone (W: form)"

# A second worktree in the group keeps the group folder alive.
wta="$(mk_worktree "$TMPDIR/repoA" keep-me)"
mkdir -p "$WT/repoA"   # group recreated by mk_worktree
wtb_branch=drop-me
git -C "$TMPDIR/repoA" worktree add -q -b "$wtb_branch" "$WT/repoA/$wtb_branch" >/dev/null 2>&1
prune "W:$WT/repoA/$wtb_branch" >/dev/null 2>&1 || fail "prune of one-of-two worktrees failed"
[ -d "$wta" ] || fail "sibling worktree should survive"
[ -f "$WT/repoA/.cockpit-repo" ] || fail "non-empty group should keep its marker"
prune "W:$wta" >/dev/null 2>&1 || fail "prune of last worktree failed"
[ -e "$WT/repoA" ] && fail "group folder should be cleaned once empty"

# --- worktree-mode feature: prune deregisters source worktrees ----------
FEATURE_MODE="worktree"
feature feat-w "$TMPDIR/repoA" "$TMPDIR/repoB" >/dev/null 2>&1 \
  || fail "setup: worktree-mode feature creation failed"
fdir="$WT/features/feat-w"
[ -f "$fdir/repoA/.git" ] || fail "setup: feature repoA not a worktree"
prune --feature feat-w >/dev/null 2>&1 || fail "prune --feature (worktree mode) failed"
[ -e "$fdir" ] && fail "feature folder should be gone"
for r in repoA repoB; do
  if git -C "$TMPDIR/$r" worktree list --porcelain | grep -q "features/feat-w"; then
    fail "$r still has a dangling worktree registration after feature prune"
  fi
done
FEATURE_MODE=""

# --- clone-mode feature: prune removes the folder -----------------------
feature feat-c "$TMPDIR/repoA" >/dev/null 2>&1 \
  || fail "setup: clone-mode feature creation failed"
[ -d "$WT/features/feat-c/repoA/.git" ] || fail "setup: clone-mode feature missing"
prune "F:$WT/features/feat-c" >/dev/null 2>&1 || fail "prune F:<feature> failed"
[ -e "$WT/features/feat-c" ] && fail "clone-mode feature folder should be gone"

# --- guards -------------------------------------------------------------
if prune --feature does-not-exist >/dev/null 2>&1; then
  fail "pruning a missing feature should fail"
fi
if prune --worktree "$TMPDIR/repoA" no-such-branch >/dev/null 2>&1; then
  fail "pruning a missing worktree branch should fail"
fi
# Refuse to prune the main worktree of a repo.
if prune "W:$TMPDIR/repoB" >/dev/null 2>&1; then
  fail "pruning the main worktree should be refused"
fi

printf 'ok - prune\n'
