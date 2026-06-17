#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cockpit-feature.XXXXXX")"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT HUP INT TERM

# Isolated, deterministic git identity (never touch the user's global config).
export GIT_AUTHOR_NAME=cockpit-test GIT_AUTHOR_EMAIL=test@cockpit
export GIT_COMMITTER_NAME=cockpit-test GIT_COMMITTER_EMAIL=test@cockpit
export HOME="$TMPDIR/home"
export FEATURE_MODE=""   # read by the tmux stub for @cockpit-feature-mode
mkdir -p "$HOME" "$TMPDIR/bin"

WT="$TMPDIR/worktrees"

mk_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" checkout -q -b main
  : >"$dir/README"
  printf 'SECRET=1\n' >"$dir/.env"          # gitignored env, must be copied
  printf '# agents\n' >"$dir/AGENTS.md"     # gitignored agent notes, copied
  ln -s AGENTS.md "$dir/CLAUDE.md"          # symlink -> must be dereferenced
  mkdir -p "$dir/sub"
  printf 'NESTED=1\n' >"$dir/sub/.env"
  printf '.env\nAGENTS.md\nCLAUDE.md\n' >"$dir/.gitignore"
  git -C "$dir" add README .gitignore
  git -C "$dir" commit -q -m init
}

mk_repo "$TMPDIR/repoA"
mk_repo "$TMPDIR/repoB"
mk_repo "$TMPDIR/nested/repoA"   # same basename as repoA -> dedupe path

# Minimal tmux stub: enough for open-project.sh to "create" and attach.
# @cockpit-feature-mode is sourced from the FEATURE_MODE env at runtime.
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

run_feature() {
  PATH="$TMPDIR/bin:$PATH" TMUX='' "$ROOT/scripts/open-feature.sh" "$@"
}

# --- default mode is clone ----------------------------------------------
FEATURE_MODE=""
run_feature feat-x "$TMPDIR/repoA" "$TMPDIR/repoB" >/dev/null 2>&1 \
  || fail "open-feature.sh exited non-zero on clone path"

fdir="$WT/features/feat-x"
[ -d "$fdir/repoA/.git" ] || fail "repoA was not cloned (.git should be a dir)"
[ -d "$fdir/repoB/.git" ] || fail "repoB was not cloned"

br="$(git -C "$fdir/repoA" branch --show-current)"
[ "$br" = "feat-x" ] || fail "clone not on new branch feat-x (got: $br)"

# A clone is independent of the source repo (not a linked worktree).
# git reports resolved paths, so compare against the resolved clone path.
clone_real="$(cd "$fdir/repoA" && pwd -P)"
if git -C "$TMPDIR/repoA" worktree list --porcelain | grep -q "$clone_real"; then
  fail "clone should not be registered as a worktree of the source"
fi

# Gitignored local files were copied in, at the right relative paths.
[ -f "$fdir/repoA/.env" ] || fail "root .env not copied into clone"
[ -f "$fdir/repoA/sub/.env" ] || fail "nested sub/.env not copied into clone"
grep -q 'SECRET=1' "$fdir/repoA/.env" || fail ".env contents not copied"
[ -f "$fdir/repoA/AGENTS.md" ] || fail "AGENTS.md not copied into clone"
# CLAUDE.md was a symlink in the source: it must arrive as a real file
# (dereferenced) carrying the linked content, not a symlink.
[ -f "$fdir/repoA/CLAUDE.md" ] || fail "CLAUDE.md (symlink) not copied into clone"
if [ -L "$fdir/repoA/CLAUDE.md" ]; then
  fail "CLAUDE.md should be a real file (dereferenced), not a symlink"
fi
grep -q '# agents' "$fdir/repoA/CLAUDE.md" || fail "CLAUDE.md symlink not dereferenced to its target content"

# --- recreate: an existing feature is wiped and rebuilt -----------------
run_feature feat-x "$TMPDIR/repoA" >/dev/null 2>&1 \
  || fail "recreating an existing feature should succeed"
[ -d "$fdir/repoA/.git" ] || fail "recreated repoA missing"
if [ -e "$fdir/repoB" ]; then
  fail "old repoB should be gone after recreate"
fi

# --- worktree mode (opt-in) ---------------------------------------------
FEATURE_MODE="worktree"
run_feature feat-w "$TMPDIR/repoA" >/dev/null 2>&1 \
  || fail "open-feature.sh exited non-zero in worktree mode"
wdir="$WT/features/feat-w/repoA"
[ -f "$wdir/.git" ] || fail "worktree mode should produce a .git file, not a dir"
wreal="$(cd "$wdir" && pwd -P)"
git -C "$TMPDIR/repoA" worktree list --porcelain | grep -q "$wreal" \
  || fail "worktree not registered with the source repo"
[ -f "$wdir/.env" ] || fail ".env not copied into worktree"
FEATURE_MODE=""

# --- dedupe: two repos sharing a basename -------------------------------
run_feature feat-y "$TMPDIR/repoA" "$TMPDIR/nested/repoA" >/dev/null 2>&1 \
  || fail "open-feature.sh exited non-zero on dedupe path"
[ -d "$WT/features/feat-y/repoA" ] || fail "first repoA folder missing"
[ -d "$WT/features/feat-y/repoA-2" ] || fail "deduped repoA-2 folder missing"

# --- guard: invalid name and no repos -----------------------------------
if run_feature "bad/name" "$TMPDIR/repoA" >/dev/null 2>&1; then
  fail "feature name with slash should fail"
fi
if run_feature feat-z >/dev/null 2>&1; then
  fail "feature with no repos should fail"
fi

printf 'ok - feature\n'
