#!/usr/bin/env bash
# Keeps the scheduled workflows running. In a public repository GitHub
# disables every scheduled workflow after 60 days without repository
# activity (state disabled_inactivity), and update.yaml's daily re-sign is
# what keeps the index's 14-day Valid-Until from passing. Three workflows run
# `refresh` (update.yaml daily, staleness.yaml daily, keepalive.yaml twice a
# week), each over every scheduled workflow, so any one of them still running
# keeps or brings back all the others. staleness.yaml runs `check` first.
#
# Usage: keep-schedules-alive.sh refresh [--dry-run]
#        keep-schedules-alive.sh check
# Env:   GH_REPO        owner/repo (required; gh reads it too)
#        GH_TOKEN       the workflow's GITHUB_TOKEN: actions: write for
#                       refresh, actions: read for check and --dry-run
#        WORKFLOWS_DIR  TEST ONLY: instead of .github/workflows
#
# The scheduled workflows are the files in .github/workflows with a
# `schedule:` trigger. For each, by its state on GitHub:
#
#   refresh  active               enable it again (PUT .../enable): renews it
#                                 before GitHub would disable it
#            disabled_inactivity  enable it, and fail at the end, so the run
#                                 fails and the maintainer hears of it
#            disabled_manually    leave it: someone turned it off on purpose
#                                 (update.yaml during a key recovery)
#            not known to GitHub  skip (not on the default branch yet)
#   check    disabled_inactivity  fail (staleness.yaml opens an issue);
#                                 nothing else fails. Also prints the days
#                                 since the last commit on the default branch.
#
# --dry-run prints the enable calls instead of making them (pull requests).
# Prints one line per workflow, "<file> <state>: <what was done>", on stdout.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

MODE=${1:-}
DRY_RUN=false
case "$MODE ${2:-}" in
  "refresh ") ;;
  "refresh --dry-run") DRY_RUN=true ;;
  "check ") ;;
  *) die "usage: keep-schedules-alive.sh refresh [--dry-run] | check" ;;
esac
readonly MODE DRY_RUN

GH_REPO=${GH_REPO:-}
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GH_REPO must be owner/repo, not '$GH_REPO'"
readonly GH_REPO
WORKFLOWS_DIR=${WORKFLOWS_DIR:-$REPO_ROOT/.github/workflows}
readonly WORKFLOWS_DIR

# Workflow states, as the REST API reports them.
readonly STATE_ACTIVE=active
readonly STATE_INACTIVITY=disabled_inactivity
readonly STATE_MANUAL=disabled_manually
# GitHub's limit, and when check starts to mention it.
readonly INACTIVITY_LIMIT_DAYS=60
readonly INACTIVITY_NOTICE_DAYS=45

# scheduled_workflows: the file names of the workflows with a schedule
# trigger (a `schedule:` key directly under `on:`), one per line.
scheduled_workflows() {
  local file
  for file in "$WORKFLOWS_DIR"/*.yaml "$WORKFLOWS_DIR"/*.yml; do
    [ -f "$file" ] || continue
    if grep -qE '^  schedule:' "$file"; then basename "$file"; fi
  done | sort
}

# workflow_states: "<path> <state>" for each workflow GitHub knows.
workflow_states() {
  gh api --paginate "repos/$GH_REPO/actions/workflows" \
    | jq -r '.workflows[] | "\(.path) \(.state)"'
}

# state_of <file> <states>: that workflow's state, or nothing.
state_of() {
  awk -v path=".github/workflows/$1" '$1 == path {print $2; exit}' <<<"$2"
}

# enable <file>: PUT .../enable (or, with --dry-run, say so).
enable() {
  if [ "$DRY_RUN" = true ]; then
    log "dry run: would PUT repos/$GH_REPO/actions/workflows/$1/enable"
    return 0
  fi
  gh api --silent -X PUT "repos/$GH_REPO/actions/workflows/$1/enable"
}

# days_since_last_commit: whole days since the newest commit on the default
# branch (the commits API lists it first without a sha).
days_since_last_commit() {
  local date
  date=$(gh api "repos/$GH_REPO/commits?per_page=1" | jq -r '.[0].commit.committer.date // empty')
  [ -n "$date" ] || die "no commit date from the GitHub API"
  printf '%s %s\n' "$date" $(( ($(now_epoch) - $(date -u -d "$date" +%s)) / SECONDS_PER_DAY ))
}

refresh() {
  local files=$1 states=$2 file state renewed=() failed=() enabled="enabled again" done=renewed
  if [ "$DRY_RUN" = true ]; then enabled="dry run: not enabled" done="would renew (dry run)"; fi
  for file in $files; do
    state=$(state_of "$file" "$states")
    case $state in
      "")
        echo "$file unknown: skipped (not on the default branch yet)" ;;
      "$STATE_ACTIVE" | "$STATE_INACTIVITY")
        if enable "$file"; then
          if [ "$state" = "$STATE_INACTIVITY" ]; then
            echo "$file $state: re-enabled ($enabled)"
            renewed+=("$file")
          else
            echo "$file $state: $done"
          fi
        else
          echo "$file $state: enable FAILED"
          failed+=("$file")
        fi ;;
      "$STATE_MANUAL")
        echo "$file $state: left alone (turned off by hand)" ;;
      *)
        echo "$file $state: left alone" ;;
    esac
  done
  [ "${#failed[@]}" -eq 0 ] || die "could not enable: ${failed[*]} (does the job have actions: write?)"
  [ "${#renewed[@]}" -eq 0 ] \
    || die "GitHub had disabled ${renewed[*]} for inactivity ($enabled). Check why the keep-alive did not hold (SECURITY.md, \"Index freshness\")."
}

check() {
  local files=$1 states=$2 file state disabled=() last
  for file in $files; do
    state=$(state_of "$file" "$states")
    echo "$file ${state:-unknown}"
    if [ "$state" = "$STATE_INACTIVITY" ]; then disabled+=("$file"); fi
  done
  last=$(days_since_last_commit)
  echo "last commit on the default branch: ${last% *} (${last#* } days ago)"
  if [ "${last#* }" -ge "$INACTIVITY_NOTICE_DAYS" ]; then
    echo "no commit for ${last#* } days: past day $INACTIVITY_LIMIT_DAYS the schedules rely on the keep-alive alone"
  fi
  [ "${#disabled[@]}" -eq 0 ] \
    || die "disabled by GitHub for inactivity: ${disabled[*]}"
}

main() {
  local files states
  files=$(scheduled_workflows)
  [ -n "$files" ] || die "no scheduled workflow found in $WORKFLOWS_DIR"
  states=$(workflow_states) || die "could not list the workflows of $GH_REPO"
  [ -n "$states" ] || die "the GitHub API listed no workflows for $GH_REPO"
  "$MODE" "$files" "$states"
}

main
