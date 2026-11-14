#!/usr/bin/env bash
# Tests of check-dco.sh, offline, in a local git repository:
#
#   accepts   a commit made with `git commit -s`; a sign-off that differs from
#             the author only in case and spaces; the author's among other
#             sign-offs; no commits at all; a merge commit without one; main's
#             unsigned commits merged into the branch, once the base branch
#             is a base; Dependabot's commit in Dependabot's pull request; a
#             keep-alive commit
#   refuses   no sign-off; another person's; the author's name with another
#             address; a sign-off outside the trailer block; one unsigned
#             commit among signed ones (and names it, only it); main's
#             unsigned commits when only the old base is given; Dependabot's
#             identity in someone else's pull request; a keep-alive commit
#             with an extra file; a base or head that is not a commit; too
#             few arguments; a commit listing that fails (it must not read
#             as no commits)
#
# Usage: test-dco.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
CHECKER=$SCRIPTS_DIR/check-dco.sh

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>"$T/err.log"; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -E 'ERROR' "$T/err.log" | tail -1)"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log" "$T/err.log"
  fi
}
# expect_log <description> <fixed-string>: the last run's stderr has it.
expect_log() {
  if grep -qF -- "$2" "$T/err.log"; then pass "$1"; else fail "$1: no '$2'"; cat "$T/err.log"; fi
}
# expect_no_log <description> <fixed-string>: the last run's stderr lacks it.
expect_no_log() {
  if grep -qF -- "$2" "$T/err.log"; then fail "$1: has '$2'"; cat "$T/err.log"; else pass "$1"; fi
}

# Git, isolated from the user's configuration (no signing, no hooks).
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Ada Lovelace"
git config --global user.email "ada@example.invalid"
git config --global init.defaultBranch main
git config --global commit.gpgsign false
unset GIT_DIR GIT_WORK_TREE

AUTHOR='Ada Lovelace <ada@example.invalid>'
DEPENDABOT='dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'

git init -q "$T/repo"
cd "$T/repo"
git commit -q --allow-empty -m "root"
BASE=$(git rev-parse HEAD)

# check <pr-author> <head> <base>...: the checker, in this repository.
check() { bash "$CHECKER" "$@"; }

# branch_with <name> <message>: a new branch from BASE with one commit that
# adds the file <name>, the message given (its trailers included); prints
# the commit.
branch_with() {
  git checkout -q -B "$1" "$BASE"
  printf '%s\n' "$1" > "$1"
  git add -- "$1"
  git commit -q -m "$2"
  git rev-parse HEAD
}

# --- Sign-offs ---------------------------------------------------------------

git checkout -q -B signed-s "$BASE"
echo a > a && git add a && git commit -q -s -m "add a"
expect accept "a commit made with git commit -s" check octocat "$(git rev-parse HEAD)" "$BASE"
expect_log "it is reported as signed off" "signed off: "

head=$(branch_with case "add case

Signed-off-by:   ada LOVELACE   <ADA@example.invalid>  ")
expect accept "a sign-off that differs only in case and spaces" check octocat "$head" "$BASE"

head=$(branch_with several "add several

Co-authored-by: Charles Babbage <charles@example.invalid>
Signed-off-by: Charles Babbage <charles@example.invalid>
Signed-off-by: $AUTHOR")
expect accept "the author's sign-off among others" check octocat "$head" "$BASE"

head=$(branch_with innerspace "add innerspace

Signed-off-by: Ada   Lovelace < ada@example.invalid >")
expect accept "a sign-off with spaces inside the name's runs and the address's brackets" check octocat "$head" "$BASE"

expect accept "no commits at all" check octocat "$BASE" "$BASE"

head=$(branch_with none "add none")
expect refuse "no sign-off" check octocat "$head" "$BASE"
expect_log "the refusal says how to sign off" "git rebase --signoff"
expect_log "it says another author must sign off their own commit" "A commit another person wrote"

head=$(branch_with other "add other

Signed-off-by: Charles Babbage <charles@example.invalid>")
expect refuse "another person's sign-off only" check octocat "$head" "$BASE"

head=$(branch_with address "add address

Signed-off-by: Ada Lovelace <ada@elsewhere.invalid>")
expect refuse "the author's name with another address" check octocat "$head" "$BASE"

head=$(branch_with body "add body

Signed-off-by: $AUTHOR

This paragraph comes after it, so it is no trailer.")
expect refuse "a sign-off outside the trailer block" check octocat "$head" "$BASE"

git checkout -q -B mixed "$BASE"
echo 1 > m1 && git add m1 && git commit -q -s -m "mixed one"
echo 2 > m2 && git add m2 && git commit -q -m "mixed two, unsigned"
echo 3 > m3 && git add m3 && git commit -q -s -m "mixed three"
expect refuse "one unsigned commit among signed ones" check octocat "$(git rev-parse HEAD)" "$BASE"
expect_log "it names the unsigned commit" "mixed two, unsigned"
expect_no_log "it does not name the signed ones as unsigned" "NO SIGN-OFF by $AUTHOR: $(git rev-parse --short HEAD) mixed three"

# --- Merges and main ---------------------------------------------------------

# main moves on with an unsigned commit (as a squash merge by GitHub would),
# and the branch merges main in: the merge and main's commit are not the
# pull request's.
git checkout -q -B feature "$BASE"
echo f > f && git add f && git commit -q -s -m "feature"
git checkout -q main
echo n > n && git add n && git commit -q -m "a later commit on main, unsigned"
git checkout -q feature
git merge -q --no-edit main
head=$(git rev-parse HEAD)
expect accept "a merge commit without a sign-off" check octocat "$head" "$BASE" main
expect refuse "main's unsigned commit, with only the old base given" check octocat "$head" "$BASE"
expect_log "it names main's commit" "a later commit on main, unsigned"

# --- Dependabot --------------------------------------------------------------

git checkout -q -B dependabot "$BASE"
echo d > d && git add d
git -c user.name='dependabot[bot]' -c user.email='49699333+dependabot[bot]@users.noreply.github.com' \
  commit -q -m "build(deps): bump something

Signed-off-by: dependabot[bot] <support@github.com>"
head=$(git rev-parse HEAD)
expect accept "Dependabot's commit in Dependabot's pull request" check 'dependabot[bot]' "$head" "$BASE"
expect_log "it is reported as exempt" "exempt (Dependabot)"
expect refuse "Dependabot's identity in someone else's pull request" check octocat "$head" "$BASE"
expect_log "it names Dependabot as the author" "NO SIGN-OFF by $DEPENDABOT"

# --- The keep-alive commit ---------------------------------------------------

# keepalive_commit_on <branch> <extra-file|"">: a keep-alive commit on a new
# branch from BASE, by github-actions[bot] with the fixed message; prints it.
keepalive_commit_on() {
  git checkout -q -B "$1" "$BASE"
  printf '%s\n' "2026-11-14T16:00:00Z" > "$KEEPALIVE_FILE"
  git add -- "$KEEPALIVE_FILE"
  if [ -n "$2" ]; then echo x > "$2" && git add -- "$2"; fi
  git -c user.name="$GITHUB_ACTIONS_BOT_LOGIN" -c user.email="$GITHUB_ACTIONS_BOT_EMAIL" \
    commit -q -m "$KEEPALIVE_COMMIT_MESSAGE"
  git rev-parse HEAD
}
head=$(keepalive_commit_on keepalive "")
expect accept "a keep-alive commit" check octocat "$head" "$BASE"
expect_log "it is reported as exempt" "exempt (keep-alive commit)"
head=$(keepalive_commit_on keepalive-extra extra)
expect refuse "a keep-alive commit with an extra file" check octocat "$head" "$BASE"

# --- A failing commit listing ------------------------------------------------

# A git whose `rev-list` fails must not read as "no commits": the check refuses.
mkdir "$T/shim"
real_git=$(command -v git)
cat > "$T/shim/git" <<SHIM
#!$(command -v bash)
[ "\$1" = rev-list ] && exit 1
exec $real_git "\$@"
SHIM
chmod +x "$T/shim/git"
head=$(branch_with listing "add listing

Signed-off-by: $AUTHOR")
expect refuse "a commit listing that fails" env PATH="$T/shim:$PATH" bash "$CHECKER" octocat "$head" "$BASE"
expect_log "it says the listing failed" "cannot list the pull request's commits"

# --- Arguments ---------------------------------------------------------------

expect refuse "a base that is not a commit" check octocat "$head" 0000000000000000000000000000000000000000
expect_log "it says what is wrong" "not a commit in this repository"
expect refuse "a head that is not a commit" check octocat no-such-branch "$BASE"
expect refuse "too few arguments" check octocat "$head"

echo
if [ "$fails" -ne 0 ]; then
  die "$fails test(s) failed"
fi
echo "test-dco: all passed"
