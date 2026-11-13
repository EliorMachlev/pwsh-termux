#!/usr/bin/env bash
# Pushes one keep-alive commit to main, so that GitHub's 60-day rule (no
# repository activity: every scheduled workflow is disabled) never applies.
# Only commits on the default branch count as activity, and main's ruleset
# requires signed commits, a pull request and passing status checks, so the
# commit is pushed with a deploy key that the main-only ruleset lets bypass
# (docs/markDown/engineering/ci-cd.md, "Keep-alive commit"). Run by
# .github/workflows/keepalive-commit.yaml, weekly, in the main-only
# environment `keepalive` that holds the key.
#
# Usage: keepalive-commit.sh [--dry-run] [--ignore-age]
#        keepalive-commit.sh check <commit> <parent>
# Env:   GH_REPO               owner/repo (required)
#        GH_TOKEN              the workflow's GITHUB_TOKEN with statuses: write
#                              (not used by --dry-run)
#        KEEPALIVE_DEPLOY_KEY  the deploy key's private key (OpenSSH); needed
#                              for an SSH remote. It goes into an ssh-agent
#                              through a pipe and is never written to disk.
#        KEEPALIVE_REMOTE      where main is fetched from and pushed to;
#                              default git@github.com:$GH_REPO.git. The pull
#                              request dry run uses https; tests a file:// one.
#
# What it does:
#   1. fetches main's tip (depth 1) into a temporary repository;
#   2. skips (exit 0) if the tip's commit date is less than
#      KEEPALIVE_MIN_AGE_DAYS old: real activity already counts;
#   3. builds one commit on that tip that sets keep.alive to the current UTC
#      time, as github-actions[bot], with the fixed message;
#   4. refuses to push unless keepalive_commit_problems (lib/common.sh) finds
#      nothing, its one parent is the fetched tip, and the raw NUL-separated
#      list of paths it changes from that tip is exactly "keep.alive\0";
#   5. pushes it to refs/heads/main; if refused and main has moved meanwhile,
#      starts again from 1, at most KEEPALIVE_PUSH_RETRIES times;
#   6. posts the commit status keepalive/pushed (success) on it, which
#      audit-main-commits.sh requires of every keep-alive commit.
# --dry-run does 1 to 4 and pushes nothing. --ignore-age skips step 2: the
# pull request dry run builds against the real main with it, and the
# maintainer starts the workflow with it once to test the ruleset set-up.
# `check` runs step 4 alone on a commit in the current repository (tests).
# Prints the new commit's SHA on stdout when it pushes (or would).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

# A commit on main younger than this already counts as activity; GitHub's
# limit is 60 days and the workflow runs weekly, so a keep-alive commit lands
# between day 30 and 37 of a quiet spell, and never while work goes on.
readonly KEEPALIVE_MIN_AGE_DAYS=30
# How often a push refused because main moved is rebuilt and tried again.
readonly KEEPALIVE_PUSH_RETRIES=3
readonly MAIN_REF=refs/heads/main
readonly FETCHED_REF=refs/remotes/origin/main
# GitHub's SSH host key (https://api.github.com/meta, "ssh_keys"; also in
# GitHub's docs, "GitHub's SSH key fingerprints"): the push trusts no other.
readonly GITHUB_SSH_HOST_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
# The deploy key's lifetime in the agent, in seconds: the job's length.
readonly AGENT_KEY_LIFETIME_SECONDS=900

usage() { die "usage: keepalive-commit.sh [--dry-run] [--ignore-age] | check <commit> <parent>"; }

DRY_RUN=false
IGNORE_AGE=false
case "${1:-} ${2:-}" in
  " ") ;;
  "--dry-run ") DRY_RUN=true ;;
  "--ignore-age ") IGNORE_AGE=true ;;
  "--dry-run --ignore-age") DRY_RUN=true IGNORE_AGE=true ;;
  "check "*) [ $# -eq 3 ] || usage ;;
  *) usage ;;
esac
[ "${1:-}" = check ] || [ $# -le 2 ] || usage
readonly DRY_RUN IGNORE_AGE

# guard_commit <commit> <parent>: dies unless the commit is a keep-alive
# commit whose one parent is <parent>.
guard_commit() {
  local commit=$1 parent=$2 problems actual_parent
  problems=$(keepalive_commit_problems "$commit")
  [ -z "$problems" ] || die "refusing $commit: $(paste -sd ';' - <<<"$problems")"
  actual_parent=$(git rev-parse "$commit^1")
  [ "$actual_parent" = "$(git rev-parse "$parent^{commit}")" ] \
    || die "refusing $commit: its parent $actual_parent is not main's tip $parent"
  # Again against <parent> itself, on the raw NUL-separated path list.
  git diff -z --name-only --no-renames "$parent" "$commit" | is_keepalive_path_list \
    || die "refusing $commit: the paths it changes from $parent are not exactly $KEEPALIVE_FILE"
}

if [ "${1:-}" = check ]; then
  guard_commit "$2" "$3"
  log "$2 is a keep-alive commit on $3"
  exit 0
fi

GH_REPO=${GH_REPO:-}
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GH_REPO must be owner/repo, not '$GH_REPO'"
readonly GH_REPO
REMOTE=${KEEPALIVE_REMOTE:-git@github.com:$GH_REPO.git}
readonly REMOTE

# Never push from anything but main's own workflow run (the environment's
# branch policy says the same; this does not rely on it).
if [ "${GITHUB_ACTIONS:-}" = true ] && [ "$DRY_RUN" = false ] && [ "${GITHUB_REF:-}" != "$MAIN_REF" ]; then
  die "refusing to push from ${GITHUB_REF:-an unknown ref}: only a run on $MAIN_REF may"
fi

WORK=$(mktemp -d)
AGENT_STARTED=false
cleanup() {
  if [ "$AGENT_STARTED" = true ]; then ssh-agent -k >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

is_ssh_remote() { [[ "$REMOTE" == git@* || "$REMOTE" == ssh://* ]]; }

# start_deploy_key_agent: an ssh-agent holding the deploy key, and git's ssh
# pinned to GitHub's host key. The key goes through a pipe, never a file, and
# leaves the environment.
start_deploy_key_agent() {
  [ -n "${KEEPALIVE_DEPLOY_KEY:-}" ] \
    || die "KEEPALIVE_DEPLOY_KEY is not set (the keepalive environment's secret)"
  eval "$(ssh-agent -s)" >/dev/null
  AGENT_STARTED=true
  printf '%s\n' "$KEEPALIVE_DEPLOY_KEY" | ssh-add -q -t "$AGENT_KEY_LIFETIME_SECONDS" - \
    || die "ssh-add refused KEEPALIVE_DEPLOY_KEY"
  unset KEEPALIVE_DEPLOY_KEY
  printf 'github.com %s\n' "$GITHUB_SSH_HOST_KEY" > "$WORK/known_hosts"
  export GIT_SSH_COMMAND="ssh -F none -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$WORK/known_hosts -o HostKeyAlgorithms=ssh-ed25519"
}

# fetch_main_tip: main's tip SHA, fetched (depth 1) into the work repository.
fetch_main_tip() {
  git fetch -q --depth=1 --no-tags "$REMOTE" "+$MAIN_REF:$FETCHED_REF" \
    || die "could not fetch $MAIN_REF from $REMOTE"
  git rev-parse "$FETCHED_REF^{commit}"
}

# days_since <commit>: whole days since its committer date (negative if in
# the future).
days_since() { echo $(( ($(now_epoch) - $(git log -1 --format=%ct "$1")) / SECONDS_PER_DAY )); }

# build_commit <parent>: a commit on <parent> that sets keep.alive to now;
# prints its SHA. Plumbing only: no work tree, no hooks, no signing.
build_commit() {
  local parent=$1 now timestamp blob tree
  now=$(now_epoch)
  timestamp=$(date -u -d "@$now" +"$KEEPALIVE_TIMESTAMP_FORMAT")
  blob=$(printf '%s\n' "$timestamp" | git hash-object -w --stdin)
  GIT_INDEX_FILE=$WORK/index git read-tree "$parent"
  GIT_INDEX_FILE=$WORK/index git update-index --add --cacheinfo "$KEEPALIVE_FILE_MODE,$blob,$KEEPALIVE_FILE"
  tree=$(GIT_INDEX_FILE=$WORK/index git write-tree)
  rm -f "$WORK/index"
  printf '%s\n' "$KEEPALIVE_COMMIT_MESSAGE" \
    | GIT_AUTHOR_NAME=$GITHUB_ACTIONS_BOT_LOGIN GIT_AUTHOR_EMAIL=$GITHUB_ACTIONS_BOT_EMAIL \
      GIT_COMMITTER_NAME=$GITHUB_ACTIONS_BOT_LOGIN GIT_COMMITTER_EMAIL=$GITHUB_ACTIONS_BOT_EMAIL \
      GIT_AUTHOR_DATE="@$now +0000" GIT_COMMITTER_DATE="@$now +0000" \
      git commit-tree --no-gpg-sign "$tree" -p "$parent"
}

# run_url: this workflow run's page, or nothing outside Actions.
run_url() {
  if [ -n "${GITHUB_RUN_ID:-}" ]; then
    echo "${GITHUB_SERVER_URL:-https://github.com}/$GH_REPO/actions/runs/$GITHUB_RUN_ID"
  fi
}

main() {
  local attempt tip age commit previous
  git init -q --bare "$WORK/repo"
  export GIT_DIR=$WORK/repo
  if is_ssh_remote; then start_deploy_key_agent; fi
  tip=$(fetch_main_tip)
  for ((attempt = 0; attempt <= KEEPALIVE_PUSH_RETRIES; attempt++)); do
    age=$(days_since "$tip")
    if [ "$age" -lt "$KEEPALIVE_MIN_AGE_DAYS" ] && [ "$IGNORE_AGE" = false ]; then
      log "skipped: main's newest commit ($tip) is $age day(s) old, under $KEEPALIVE_MIN_AGE_DAYS; it already counts as activity"
      return 0
    fi
    commit=$(build_commit "$tip")
    guard_commit "$commit" "$tip"
    if [ "$DRY_RUN" = true ]; then
      log "dry run: would push $commit (on $tip, $age day(s) old) to $MAIN_REF"
      echo "$commit"
      return 0
    fi
    if git push -q "$REMOTE" "$commit:$MAIN_REF"; then
      log "pushed $commit to $MAIN_REF (on $tip)"
      post_keepalive_status "$GH_REPO" "$commit" "$(run_url)" \
        || die "pushed $commit but could not post the $KEEPALIVE_STATUS_CONTEXT status (does the job have statuses: write?); the audit will flag it"
      echo "$commit"
      return 0
    fi
    previous=$tip
    tip=$(fetch_main_tip)
    [ "$tip" != "$previous" ] \
      || die "the push was refused and main has not moved: not a race (is the deploy key a bypass actor of main's ruleset?)"
    log "main moved to $tip during the push; building again"
  done
  die "main kept moving: gave up after $KEEPALIVE_PUSH_RETRIES retries"
}

main
