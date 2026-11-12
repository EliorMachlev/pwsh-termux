#!/usr/bin/env bash
# Tests of keep-schedules-alive.sh, offline, with a stub `gh` that answers
# from fixtures and records every call: which workflows count as scheduled,
# what refresh enables (and what it leaves alone), when refresh and check
# fail, and that --dry-run calls nothing that writes. Runs on Termux and on
# CI; touches nothing outside a temporary folder.
#
# Usage: test-keepalive.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
KEEPALIVE=$SCRIPTS_DIR/keep-schedules-alive.sh

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>&1; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -E 'ERROR' "$T/out.log" | tail -1)"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log"
  fi
}
# expect_line <description> <fixed-string>: the last run printed that line.
expect_line() {
  if grep -qxF -- "$2" "$T/out.log"; then pass "$1"; else fail "$1: no line '$2'"; cat "$T/out.log"; fi
}
# expect_calls <description> <expected calls, one per line>: what the stub
# recorded for writes (PUT), in order.
expect_calls() {
  local got
  got=$(grep -E '^api .*-X PUT' "$T/calls.log" || true)
  if [ "$got" = "$2" ]; then pass "$1"; else fail "$1: got [$got], expected [$2]"; fi
}

# The stub gh: GET the workflow list and the newest commit from fixtures,
# PUT .../enable answers 204 unless the workflow is in $T/enable-fails.
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
case "$*" in
  "api --paginate repos/o/r/actions/workflows")
    cat "$STUB_DIR/workflows.json" ;;
  "api repos/o/r/commits?per_page=1")
    cat "$STUB_DIR/commits.json" ;;
  "api --silent -X PUT repos/o/r/actions/workflows/"*"/enable")
    file=${5#repos/o/r/actions/workflows/}; file=${file%/enable}
    if grep -qxF "$file" "$STUB_DIR/enable-fails" 2>/dev/null; then
      echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1
    fi ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
chmod 755 "$T/bin/gh"
export STUB_DIR=$T PATH="$T/bin:$PATH" GH_REPO=o/r

# Workflow files: three scheduled ones (one .yml), one without a schedule,
# and one with "schedule:" only deeper down (not a trigger).
W=$T/workflows
mkdir -p "$W"
printf 'on:\n  schedule:\n    - cron: "1 1 * * *"\n  workflow_dispatch:\n' > "$W/daily.yaml"
printf 'on:\n  push:\n  schedule:\n    - cron: "1 1 * * 1"\n' > "$W/weekly.yml"
printf 'on:\n  schedule:\n    - cron: "1 1 1 1 *"\n' > "$W/yearly.yaml"
printf 'on:\n  pull_request:\n' > "$W/ci.yaml"
printf 'on:\n  push:\njobs:\n  a:\n    with:\n      schedule: weekly\n' > "$W/nested.yaml"
export WORKFLOWS_DIR=$W

# states <daily> <weekly> <yearly>: the API's workflow list ("-" leaves one out).
states() {
  local names=(daily.yaml weekly.yml yearly.yaml ci.yaml nested.yaml) values=("$1" "$2" "$3" active active) i
  {
    printf '{"total_count":5,"workflows":['
    for i in "${!names[@]}"; do
      [ "${values[$i]}" = - ] && continue
      printf '{"path":".github/workflows/%s","state":"%s"},' "${names[$i]}" "${values[$i]}"
    done
    printf '{"path":"dynamic/dependabot/dependabot-updates","state":"active"}]}\n'
  } > "$T/workflows.json"
  : > "$T/calls.log"
  : > "$T/enable-fails"
}
# last_commit <days-ago>: the newest commit on the default branch.
last_commit() {
  printf '[{"commit":{"committer":{"date":"%s"}}}]\n' \
    "$(date -u -d "@$(( $(now_epoch) - $1 * SECONDS_PER_DAY - 60 ))" +%Y-%m-%dT%H:%M:%SZ)" > "$T/commits.json"
}
last_commit 3
run() { bash "$KEEPALIVE" "$@"; }

echo "== usage"
states active active active
expect refuse "no mode"                                    run
expect refuse "an unknown mode"                            run enable
expect refuse "check --dry-run (check never writes)"       run check --dry-run
expect refuse "GH_REPO that is not owner/repo"             env GH_REPO='o/r;x' bash "$KEEPALIVE" check
expect refuse "no scheduled workflow found"                env WORKFLOWS_DIR="$T/bin" bash "$KEEPALIVE" check
printf '{"workflows":[]}\n' > "$T/workflows.json"
expect refuse "the API lists no workflows"                 run check

echo "== refresh"
states active active active
expect accept "all active: renews each"                    run refresh
expect_calls  "  one enable per scheduled workflow, nothing else" "$(printf '%s\n' \
  'api --silent -X PUT repos/o/r/actions/workflows/daily.yaml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/weekly.yml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/yearly.yaml/enable')"
expect_line   "  says so"                                  "daily.yaml active: renewed"

states disabled_inactivity active active
expect refuse "one disabled for inactivity: enabled, and the run fails" run refresh
expect_calls  "  all three enabled, the disabled one too" "$(printf '%s\n' \
  'api --silent -X PUT repos/o/r/actions/workflows/daily.yaml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/weekly.yml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/yearly.yaml/enable')"
expect_line   "  says so"                                  "daily.yaml disabled_inactivity: re-enabled (enabled again)"

states disabled_manually active active
expect accept "one turned off by hand: left alone"         run refresh
expect_calls  "  never enabled" "$(printf '%s\n' \
  'api --silent -X PUT repos/o/r/actions/workflows/weekly.yml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/yearly.yaml/enable')"

states active - active
expect accept "one not known to GitHub yet: skipped"       run refresh
expect_line   "  says so"                                  "weekly.yml unknown: skipped (not on the default branch yet)"

states active disabled_fork deleted
expect accept "other states: left alone"                   run refresh
expect_calls  "  only the active one enabled" \
  'api --silent -X PUT repos/o/r/actions/workflows/daily.yaml/enable'

states active active active
echo weekly.yml > "$T/enable-fails"
expect refuse "an enable call fails (no actions: write)"   run refresh
expect_calls  "  still tries the others" "$(printf '%s\n' \
  'api --silent -X PUT repos/o/r/actions/workflows/daily.yaml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/weekly.yml/enable' \
  'api --silent -X PUT repos/o/r/actions/workflows/yearly.yaml/enable')"

echo "== refresh --dry-run"
states active disabled_inactivity disabled_manually
expect refuse "dry run reports a disabled workflow as refresh would" run refresh --dry-run
expect_calls  "  and calls nothing that writes"            ""
states active active active
expect accept "dry run, all active"                        run refresh --dry-run
expect_calls  "  calls nothing that writes"                ""

echo "== check"
states active active disabled_manually
expect accept "active, or turned off by hand: healthy"     run check
expect_calls  "  calls nothing that writes"                ""
expect_line   "  prints the last commit's age"             "last commit on the default branch: $(jq -r '.[0].commit.committer.date' "$T/commits.json") (3 days ago)"
states active disabled_inactivity active
expect refuse "one disabled for inactivity"                run check
expect_calls  "  and does not enable it"                   ""
states active active active
last_commit 50
expect accept "50 days without a commit: healthy, with a notice" run check
expect_line   "  the notice"                               "no commit for 50 days: past day 60 the schedules rely on the keep-alive alone"
printf '[]\n' > "$T/commits.json"
expect refuse "no commit date from the API"                run check

echo "== the real workflows"
states active active active
expect accept "refresh --dry-run over .github/workflows"   env -u WORKFLOWS_DIR bash "$KEEPALIVE" refresh --dry-run
for file in update.yaml staleness.yaml keepalive.yaml key-review.yaml; do
  expect_line "  finds $file"                              "$file unknown: skipped (not on the default branch yet)"
done
if grep -q '^ci.yaml ' "$T/out.log"; then fail "  ci.yaml has no schedule"; else pass "  not ci.yaml (no schedule)"; fi

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
