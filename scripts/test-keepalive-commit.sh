#!/usr/bin/env bash
# Tests of keepalive-commit.sh and audit-main-commits.sh, offline: local git
# repositories with a bare "remote" reached by file://, a stub `gh` that
# answers from fixtures and records every call, no network and no key.
#
#   keepalive-commit.sh  pushes one keep.alive commit on an old main; skips
#                        a young main unless --ignore-age; --dry-run pushes
#                        nothing; retries when
#                        main moves during the push, gives up when it keeps
#                        moving or when a refused push is not a race; refuses
#                        an SSH remote without the key and a run off main;
#                        its guard refuses an extra file, wrong content, a
#                        merge, a wrong identity or message, a wrong parent
#   audit-main-commits.sh accepts a signed commit by a trusted account and a
#                        keep-alive commit with its status; flags a missing
#                        or forged status, an extra file, a wrong committer, a
#                        signature by an untrusted account, a rewritten main;
#                        report opens, updates (only when changed) and closes
#                        one issue, matched by its exact title
#
# Usage: test-keepalive-commit.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PUSHER=$SCRIPTS_DIR/keepalive-commit.sh
AUDITOR=$SCRIPTS_DIR/audit-main-commits.sh

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
# check <description> <command...>: passes if the command succeeds.
check() {
  local what=$1; shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}
# not <command...>: true if the command fails.
not() { ! "$@"; }
# expect_log <description> <fixed-string>: the last run's stderr has it.
expect_log() {
  if grep -qF -- "$2" "$T/err.log"; then pass "$1"; else fail "$1: no '$2'"; cat "$T/err.log"; fi
}
# expect_calls <description> <pattern> <expected lines>: the stub's recorded
# calls that match the pattern.
expect_calls() {
  local got
  got=$(grep -E -- "$2" "$T/calls.log" || true)
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1: got [$got], expected [$3]"; fi
}

# Git, isolated from the user's configuration (no signing, no hooks).
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test Author"
git config --global user.email "test@example.invalid"
git config --global init.defaultBranch main
git config --global commit.gpgsign false
unset GIT_DIR GIT_WORK_TREE GITHUB_ACTIONS GITHUB_REF GITHUB_RUN_ID KEEPALIVE_DEPLOY_KEY

# The stub gh.
#   api repos/o/r/commits/<sha>             $STUB_DIR/commits/<sha>.json, or unsigned
#   api --paginate .../<sha>/statuses?...   $STUB_DIR/statuses/<sha>.json, or []
#   api --silent -X POST .../statuses/<sha> recorded
#   issue list                              $STUB_DIR/issues.json
#   issue view <n> --json body              $STUB_DIR/issue-body.json
#   issue create|edit|comment|close         recorded
mkdir -p "$T/bin" "$T/commits" "$T/statuses"
cat > "$T/bin/gh" <<'STUB'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
case "$*" in
  "api --silent -X POST repos/o/r/statuses/"*) ;;
  "api --paginate repos/o/r/commits/"*"/statuses?per_page=100")
    sha=${3#repos/o/r/commits/}; sha=${sha%%/*}
    if [ -f "$STUB_DIR/statuses/$sha.json" ]; then cat "$STUB_DIR/statuses/$sha.json"; else echo '[]'; fi ;;
  "api repos/o/r/commits/"*)
    sha=${2#repos/o/r/commits/}
    if [ -f "$STUB_DIR/commits/$sha.json" ]; then cat "$STUB_DIR/commits/$sha.json"
    else echo '{"committer":null,"commit":{"verification":{"verified":false,"reason":"unsigned"}}}'; fi ;;
  "issue list "*) cat "$STUB_DIR/issues.json" ;;
  "issue view "*) cat "$STUB_DIR/issue-body.json" ;;
  "issue create "* | "issue edit "* | "issue comment "* | "issue close "*) ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod 755 "$T/bin/gh"
export STUB_DIR=$T PATH="$T/bin:$PATH" GH_REPO=o/r
: > "$T/calls.log"

days_ago() { echo "@$(( $(now_epoch) - $1 * SECONDS_PER_DAY )) +0000"; }

# commit_in <repo> <days-ago> <message> <file>=<content>...: a commit on the
# repository's HEAD; prints its SHA.
commit_in() {
  local repo=$1 date; date=$(days_ago "$2"); local message=$3; shift 3
  local pair
  for pair in "$@"; do
    mkdir -p "$(dirname "$repo/${pair%%=*}")"
    printf '%s' "${pair#*=}" > "$repo/${pair%%=*}"
    git -C "$repo" add "${pair%%=*}"
  done
  GIT_AUTHOR_DATE=$date GIT_COMMITTER_DATE=$date git -C "$repo" commit -q --allow-empty -m "$message"
  git -C "$repo" rev-parse HEAD
}
# as_bot <command...>: with github-actions[bot] as author and committer.
as_bot() {
  GIT_AUTHOR_NAME=$GITHUB_ACTIONS_BOT_LOGIN GIT_AUTHOR_EMAIL=$GITHUB_ACTIONS_BOT_EMAIL \
  GIT_COMMITTER_NAME=$GITHUB_ACTIONS_BOT_LOGIN GIT_COMMITTER_EMAIL=$GITHUB_ACTIONS_BOT_EMAIL "$@"
}

# new_remote <days-ago>: $T/remote.git, a bare repository whose main has two
# commits, the newest that many days old; the work clone is $T/seed.
new_remote() {
  rm -rf "$T/remote.git" "$T/seed"
  git init -q "$T/seed"
  commit_in "$T/seed" 400 "first" README=readme >/dev/null
  commit_in "$T/seed" "$1" "second" docs.md=docs >/dev/null
  git clone -q --bare "$T/seed" "$T/remote.git"
  : > "$T/calls.log"
}
remote_tip() { git --git-dir="$T/remote.git" rev-parse refs/heads/main; }
push_run() { env KEEPALIVE_REMOTE="file://$T/remote.git" bash "$PUSHER" "$@"; }

echo "== keepalive-commit.sh: pushing"
new_remote 40
before=$(remote_tip)
expect accept "main 40 days old: pushes a keep-alive commit"   push_run
after=$(remote_tip)
check "  main moved to the printed commit"                    [ "$after" = "$(cat "$T/out.log")" ]
check "  its one parent is the previous tip"                  [ "$(git --git-dir="$T/remote.git" rev-parse "$after^1")" = "$before" ]
check "  it is a keep-alive commit (no problems)" \
  [ -z "$(GIT_DIR=$T/remote.git keepalive_commit_problems "$after")" ]
check "  keep.alive holds now, to the second or so" \
  [ $(( $(now_epoch) - $(date -u -d "$(git --git-dir="$T/remote.git" cat-file blob "$after:keep.alive")" +%s) )) -le 5 ]
check "  nothing else changed" \
  [ "$(git --git-dir="$T/remote.git" diff --name-only "$before" "$after")" = keep.alive ]
expect_calls "  posts the keepalive/pushed status on it" 'statuses' \
  "api --silent -X POST repos/o/r/statuses/$after -f state=success -f context=keepalive/pushed -f description=Pushed by the keep-alive workflow -f target_url="

: > "$T/calls.log"
expect accept "again at once: main is now 0 days old, skipped" push_run
check "  main did not move"                                   [ "$(remote_tip)" = "$after" ]
expect_log "  says why"                                       "it already counts as activity"
expect_calls "  posts no status" 'statuses' ""

echo "== keepalive-commit.sh: skipping and dry run"
new_remote 29
expect accept "main 29 days old: skipped"                     push_run
check "  main did not move"                                   [ "$(remote_tip)" = "$(git -C "$T/seed" rev-parse HEAD)" ]
new_remote 40
expect accept "--dry-run on an old main"                      push_run --dry-run
check "  pushes nothing"                                      [ "$(remote_tip)" = "$(git -C "$T/seed" rev-parse HEAD)" ]
expect_log "  says what it would push"                        "dry run: would push $(cat "$T/out.log")"
expect_calls "  posts no status" 'statuses' ""
new_remote 2
expect accept "--dry-run --ignore-age on a young main builds and checks it" push_run --dry-run --ignore-age
expect_log "  says what it would push"                        "dry run: would push"
check "  pushes nothing"                                      [ "$(remote_tip)" = "$(git -C "$T/seed" rev-parse HEAD)" ]
expect accept "--ignore-age on a young main pushes (the set-up test)" push_run --ignore-age
check "  main moved"                                          [ "$(remote_tip)" = "$(cat "$T/out.log")" ]
expect refuse "--ignore-age --dry-run (the order is fixed)"   push_run --ignore-age --dry-run
expect refuse "an unknown option"                             push_run --force

echo "== keepalive-commit.sh: races and refusals"
# A pre-receive hook in the remote that, while $T/moves holds a count above
# zero, moves main to another old commit and refuses the push (as a push that
# lost a race would be refused).
new_remote 40
git -C "$T/seed" checkout -q -b other HEAD~1
moved=$(commit_in "$T/seed" 35 "moved meanwhile" other.md=other)
git -C "$T/seed" push -q "$T/remote.git" "$moved:refs/heads/other"
cat > "$T/remote.git/hooks/pre-receive" <<HOOK
#!/bin/sh
n=\$(cat "$T/moves")
[ "\$n" -gt 0 ] || exit 0
echo \$((n - 1)) > "$T/moves"
echo x >> "$T/attempts"
env -u GIT_QUARANTINE_PATH git update-ref refs/heads/main $moved
echo "rejected: main moved" >&2
exit 1
HOOK
chmod 755 "$T/remote.git/hooks/pre-receive"
echo 1 > "$T/moves"; : > "$T/attempts"
expect accept "main moves during the push: fetches again, rebuilds, pushes" push_run
check "  the commit is on the moved tip"                      [ "$(git --git-dir="$T/remote.git" rev-parse "$(remote_tip)^1")" = "$moved" ]
expect_log "  says so"                                        "main moved to $moved during the push"

original=$(git -C "$T/seed" rev-parse main)
git --git-dir="$T/remote.git" update-ref refs/heads/main "$original"
# Each refusal moves main between two old commits.
cat > "$T/remote.git/hooks/pre-receive" <<HOOK
#!/bin/sh
unset GIT_QUARANTINE_PATH
echo x >> "$T/attempts"
if [ "\$(git rev-parse refs/heads/main)" = $moved ]; then
  git update-ref refs/heads/main $original
else
  git update-ref refs/heads/main $moved
fi
echo "rejected: main moved" >&2
exit 1
HOOK
: > "$T/attempts"
expect refuse "main keeps moving: gives up"                   push_run
check "  after 1 try and 3 retries"                           [ "$(grep -c x "$T/attempts")" -eq 4 ]

printf '#!/bin/sh\necho "protected branch" >&2\nexit 1\n' > "$T/remote.git/hooks/pre-receive"
: > "$T/calls.log"
expect refuse "a refused push while main has not moved"       push_run
expect_log "  says it is not a race"                          "main has not moved"
expect_calls "  posts no status" 'statuses' ""
rm "$T/remote.git/hooks/pre-receive"

expect refuse "an SSH remote without KEEPALIVE_DEPLOY_KEY" \
  env KEEPALIVE_REMOTE=git@github.com:o/r.git bash "$PUSHER"
expect_log "  says which secret"                              "KEEPALIVE_DEPLOY_KEY is not set"
expect refuse "an SSH remote with a key ssh-add cannot load (offline: no fetch)" \
  env KEEPALIVE_REMOTE=git@github.com:o/r.git KEEPALIVE_DEPLOY_KEY=not-a-key-5f3a9 bash "$PUSHER"
expect_log "  says so"                                        "ssh-add refused KEEPALIVE_DEPLOY_KEY"
check "  and never prints the key"                            not grep -qF not-a-key-5f3a9 "$T/out.log" "$T/err.log"
expect refuse "a workflow run on another ref" \
  env GITHUB_ACTIONS=true GITHUB_REF=refs/heads/feature KEEPALIVE_REMOTE="file://$T/remote.git" bash "$PUSHER"
expect refuse "GH_REPO that is not owner/repo"                env GH_REPO='o/r;x' KEEPALIVE_REMOTE="file://$T/remote.git" bash "$PUSHER"

echo "== keepalive-commit.sh check: the guard before the push"
G=$T/guard
git init -q "$G"
base=$(commit_in "$G" 100 "base" README=readme)
good=$(as_bot commit_in "$G" 0 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-12T16:00:00Z\n')
guard() { (cd "$G" && bash "$PUSHER" check "$@"); }
expect accept "a keep-alive commit on its parent"             guard "$good" "$base"
reset_to() { git -C "$G" reset -q --hard "$1"; }
reset_to "$base"
c=$(as_bot commit_in "$G" 0 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-12T16:00:00Z\n' extra=x)
expect refuse "an extra file"                                 guard "$c" "$base"
reset_to "$base"
for bad in $'2026-11-12 16:00:00\n' $'2026-11-12T16:00:00Z' $'2026-11-12T16:00:00Z\n\n' $'2026-02-31T16:00:00Z\n' $'2026-11-12T16:00:00+00:00\n' $'rm -rf /\n'; do
  c=$(as_bot commit_in "$G" 0 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive="$bad")
  expect refuse "wrong content: $(printf '%q' "$bad")"       guard "$c" "$base"
  reset_to "$base"
done
git -C "$G" checkout -q -b side
side=$(commit_in "$G" 1 "side" side.md=s)
git -C "$G" checkout -q main
as_bot env GIT_AUTHOR_DATE="$(days_ago 0)" GIT_COMMITTER_DATE="$(days_ago 0)" \
  git -C "$G" merge -q --no-ff --no-edit -m "$KEEPALIVE_COMMIT_MESSAGE" "$side"
expect refuse "a merge (two parents)"                         guard "$(git -C "$G" rev-parse HEAD)" "$base"
reset_to "$base"
c=$(commit_in "$G" 0 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-12T16:00:00Z\n')
expect refuse "another committer"                             guard "$c" "$base"
reset_to "$base"
c=$(as_bot commit_in "$G" 0 "chore: something else" keep.alive=$'2026-11-12T16:00:00Z\n')
expect refuse "another message"                               guard "$c" "$base"
reset_to "$base"
ln -s /etc/passwd "$G/keep.alive"
git -C "$G" add keep.alive
c=$(as_bot commit_in "$G" 0 "$KEEPALIVE_COMMIT_MESSAGE")
expect refuse "keep.alive as a symbolic link"                 guard "$c" "$base"
reset_to "$base"
expect refuse "the right commit on the wrong parent"          guard "$good" "$side"

echo "== audit-main-commits.sh audit"
A=$T/audit
git init -q "$A"
baseline=$(commit_in "$A" 200 "old, unsigned, before the baseline" README=readme)
signed=$(commit_in "$A" 30 "a pull request merge" a.md=a)
printf '{"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}}}\n' > "$T/commits/$signed.json"
owner=$(commit_in "$A" 29 "the owner's signed commit" b.md=b)
printf '{"committer":{"login":"o"},"commit":{"verification":{"verified":true}}}\n' > "$T/commits/$owner.json"
status() { printf '[{"context":"%s","state":"%s","creator":{"login":"%s","id":%s}}]\n' "$2" "$3" "$4" "$5" > "$T/statuses/$1.json"; }
keepalive=$(as_bot commit_in "$A" 20 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-10-23T02:00:00Z\n')
status "$keepalive" keepalive/pushed success 'github-actions[bot]' 41898282
: > "$T/calls.log"
audit_run() { (cd "$A" && env AUDIT_BASELINE="$baseline" bash "$AUDITOR" audit "$@"); }
expect accept "a signed merge, the owner's commit, a keep-alive commit with its status" audit_run
check "  no finding"                                          [ ! -s "$T/out.log" ]
expect_calls "  never writes" 'POST|issue' ""
check "  the commit before the baseline is not checked"       not grep -q "commits/$baseline" "$T/calls.log"

# flagged <description> <sha> <reason fragment>: audit finds exactly that.
flagged() {
  expect accept "$1"                                          audit_run
  if [ "$(cut -f1 "$T/out.log")" = "$2" ] && grep -qF -- "$3" "$T/out.log"; then
    pass "  flags $2 only: $3"
  else
    fail "  expected only $2 with '$3', got: $(cat "$T/out.log")"
  fi
}
nostatus=$(as_bot commit_in "$A" 10 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-02T02:00:00Z\n')
flagged "a keep-alive commit without the status" "$nostatus" "without the keepalive/pushed status"
status "$nostatus" keepalive/pushed success mallory 1234
flagged "  its status made by another account"                "$nostatus" "without the keepalive/pushed status"
status "$nostatus" keepalive/pushed failure 'github-actions[bot]' 41898282
flagged "  a failure status"                                  "$nostatus" "without the keepalive/pushed status"
status "$nostatus" ci/other success 'github-actions[bot]' 41898282
flagged "  another context"                                   "$nostatus" "without the keepalive/pushed status"
status "$nostatus" keepalive/pushed success 'github-actions[bot]' 41898282
expect accept "  with the status: clean"                      audit_run
check "  no finding"                                          [ ! -s "$T/out.log" ]

extra=$(as_bot commit_in "$A" 9 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-03T02:00:00Z\n' .github/x.yaml=evil)
status "$extra" keepalive/pushed success 'github-actions[bot]' 41898282
flagged "keep.alive plus another file (even with a status)"   "$extra" "not only keep.alive"
git -C "$A" reset -q --hard HEAD~1

wrong=$(commit_in "$A" 8 "$KEEPALIVE_COMMIT_MESSAGE" keep.alive=$'2026-11-04T02:00:00Z\n')
status "$wrong" keepalive/pushed success 'github-actions[bot]' 41898282
flagged "a keep-alive commit by another committer"           "$wrong" "author or committer is not github-actions[bot]"
git -C "$A" reset -q --hard HEAD~1

stranger=$(commit_in "$A" 7 "signed by someone's own account" c.md=c)
printf '{"committer":{"login":"mallory"},"commit":{"verification":{"verified":true}}}\n' > "$T/commits/$stranger.json"
flagged "signed and verified, by an untrusted account"        "$stranger" "committed by mallory"
git -C "$A" reset -q --hard HEAD~1

backdated=$(commit_in "$A" 3000 "unsigned, back-dated" d.md=d)
flagged "an unsigned commit, back-dated outside the window"   "$backdated" "unsigned, and not a keep-alive commit"
git -C "$A" reset -q --hard HEAD~1

tip=$(git -C "$A" rev-parse HEAD)
expect accept "a pushed range that is a fast-forward"         audit_run "$keepalive" "$tip"
check "  no finding"                                          [ ! -s "$T/out.log" ]
expect accept "a pushed range that is not (main rewritten)"   audit_run "$signed" "$baseline"
check "  flags it"                                            grep -q "main was rewritten" "$T/out.log"
expect accept "a new branch (before is all zeros)"            audit_run 0000000000000000000000000000000000000000 "$tip"
expect refuse "a range that is not two SHAs"                  audit_run "HEAD~1" "$tip"
expect refuse "a clone without the baseline (shallow)" \
  bash -c "cd '$A' && AUDIT_BASELINE=1111111111111111111111111111111111111111 bash '$AUDITOR' audit"

echo "== audit-main-commits.sh report"
title="Unexpected unsigned commit on main"
issues() { printf '%s\n' "$1" > "$T/issues.json"; : > "$T/calls.log"; }
report_run() { printf '%s' "$1" | env RUN_URL=https://run bash "$AUDITOR" report; }
one=$(printf '%s\tEve <eve@example.invalid>\tunsigned, and not a keep-alive commit\n' "$wrong")
issues '[]'
expect refuse "findings, no issue: opens one, fails"          report_run "$one"
check "  one issue created, nothing else written" \
  [ "$(grep -cE '^issue (create|edit|comment|close)' "$T/calls.log")" -eq 1 ]
check "  titled exactly"                                      grep -qF -- "issue create --title $title --body" "$T/calls.log"
check "  lists the SHA and the author"                        grep -qF -- "| \`$wrong\` | Eve <eve@example.invalid> |" "$T/calls.log"
check "  says the deploy key may have leaked"                 grep -qF "may mean the keep-alive deploy key leaked" "$T/calls.log"
expect_log "  says why it fails"                              "1 unexpected commit(s) on main: $wrong"

body=$(sed -n '/^issue create/,$p' "$T/calls.log" | sed '1s/^issue create --title .* --body //')
issues "[{\"number\":7,\"title\":\"$title\"}]"
jq -n --arg body "$body" '{body: $body}' > "$T/issue-body.json"
expect refuse "the same findings again: no new issue, no edit" report_run "$one"
expect_calls "  nothing written" '^issue (create|edit|comment|close)' ""

two=$(printf '%s\n%s\tMallory\tsigned and verified, but committed by mallory\n' "$one" "$stranger")
issues "[{\"number\":7,\"title\":\"$title\"}]"
expect refuse "new findings: the open issue is updated"       report_run "$two"
check "  its body replaced"                                   grep -q '^issue edit 7 --body ' "$T/calls.log"
check "  and a comment added"                                 grep -q '^issue comment 7 --body The findings changed' "$T/calls.log"
check "  no second issue"                                     not grep -q '^issue create' "$T/calls.log"

issues "[{\"number\":3,\"title\":\"$title (old)\"}]"
expect refuse "an open issue with a similar title is not it"  report_run "$one"
check "  a new one is opened"                                 grep -q '^issue create' "$T/calls.log"

issues "[{\"number\":7,\"title\":\"$title\"}]"
expect accept "clean, an issue open: it is closed"            report_run ""
expect_calls "  closed with a comment" '^issue (create|edit|comment|close)' \
  "issue close 7 --comment Clean again: every audited commit on main is signed or a keep-alive commit. https://run"
issues '[]'
expect accept "clean, no issue: nothing to do"                report_run ""
expect_calls "  nothing written" '^issue (create|edit|comment|close)' ""

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
