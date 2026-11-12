#!/usr/bin/env bash
# Audits the commits on main. The keep-alive deploy key (keepalive-commit.sh)
# may bypass main's ruleset, so whoever holds it could push anything there
# unsigned. Every commit on main must therefore be one of:
#
#   signed       GitHub reports its signature verified, and its committer is
#                an account trusted to commit to main: web-flow (pull
#                request merges, Dependabot) or the repository's owner;
#   keep-alive   unsigned, but exactly the keep-alive commit
#                (keepalive_commit_problems in lib/common.sh finds nothing),
#                AND GitHub holds the commit status keepalive/pushed
#                (success) on it, created by github-actions[bot], which only
#                a workflow's GITHUB_TOKEN can do: the deploy key alone
#                cannot make one.
#
# Anything else is a finding. This is detection, not prevention: whoever can
# push to main can also change this script and its workflow
# (docs/markDown/engineering/security.md says what does prevent it).
#
# Usage: audit-main-commits.sh audit [<before> <after>]
#        audit-main-commits.sh report
# Env:   GH_REPO     owner/repo (required)
#        GH_TOKEN    contents: read and statuses: read for audit; issues:
#                    write for report
#        RUN_URL     the run, linked from the issue's comments (optional)
#        AUDIT_BASELINE  TEST ONLY: instead of AUDIT_BASELINE_COMMIT
#
# audit: runs in a full clone of main (the current directory; HEAD is main)
#   and checks, newest first: every commit after the baseline committed in
#   the last AUDIT_WINDOW_DAYS days, the newest AUDIT_MIN_COMMITS whatever
#   their dates (a back-dated commit is still checked), and, given a pushed
#   range, every commit in <before>..<after> (and a finding if <after> does
#   not contain <before>: main was rewritten). Prints one finding per line,
#   "<sha>\t<author>\t<reason>", on stdout; nothing if all is well.
# report: reads those lines on stdin and keeps one issue in step, found by
#   its exact title: opened when there are findings, its body replaced (and a
#   comment added) when they change, closed with a comment when there are
#   none. Exits 1 when there are findings.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

# How far back the audit looks, and how many commits it checks whatever
# their dates.
readonly AUDIT_WINDOW_DAYS=90
readonly AUDIT_MIN_COMMITS=50
# The last commit made before main's ruleset required signatures: it and its
# ancestors are unsigned and are not audited. After a finding has been dealt
# with (reverted, key rotated), move this to the newest commit reviewed.
readonly AUDIT_BASELINE_COMMIT=c3564f21701f9bdea53a987854f3074e8ffca5ed
# Accounts whose verified commits may be on main, besides the owner.
readonly TRUSTED_COMMITTERS=(web-flow)
readonly ISSUE_TITLE="Unexpected unsigned commit on main"
readonly ZERO_SHA=0000000000000000000000000000000000000000
readonly SHA_REGEX='^[0-9a-f]{40}$'

GH_REPO=${GH_REPO:-}
[[ "$GH_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GH_REPO must be owner/repo, not '$GH_REPO'"
readonly GH_REPO
readonly OWNER=${GH_REPO%%/*}
BASELINE=${AUDIT_BASELINE:-$AUDIT_BASELINE_COMMIT}
readonly BASELINE

# clean_text: stdin made safe for one Markdown table cell: printable ASCII
# only, no pipe, backtick or angle bracket, at most 200 characters.
clean_text() { tr -c '[:print:]' ' ' | tr '|`<>' '/'"'"'()' | cut -c1-200; }

# finding <sha> <reason>: one finding line.
finding() {
  local author
  author=$(git show -s --format='%an <%ae>' "$1" 2>/dev/null | clean_text || true)
  printf '%s\t%s\t%s\n' "$1" "${author:-unknown}" "$(printf '%s' "$2" | clean_text)"
}

# commits_to_audit [<before> <after>]: the SHAs to check, newest first, once
# each; and a finding line (prefixed "!") if the range is not a fast-forward.
commits_to_audit() {
  local since
  since=$(( $(now_epoch) - AUDIT_WINDOW_DAYS * SECONDS_PER_DAY ))
  {
    git rev-list --topo-order --max-count="$AUDIT_MIN_COMMITS" HEAD --not "$BASELINE"
    git rev-list --topo-order --format='%ct %H' --no-commit-header HEAD --not "$BASELINE" \
      | awk -v since="$since" '$1 >= since {print $2}'
    if [ $# -eq 2 ] && [ "$1" != "$ZERO_SHA" ]; then
      if git merge-base --is-ancestor "$1" "$2" 2>/dev/null; then
        git rev-list --topo-order "$1..$2"
      else
        printf '!%s\n' "$2"
      fi
    fi
  } | awk '!seen[$0]++'
}

# verified_committer <sha>: the login of the committer's GitHub account if
# GitHub reports the commit's signature verified; nothing otherwise.
verified_committer() {
  gh api "repos/$GH_REPO/commits/$1" \
    | jq -r 'if .commit.verification.verified == true then (.committer.login // "(no account)") else empty end'
}

# is_trusted_committer <login>
is_trusted_committer() {
  local login
  [ "$1" = "$OWNER" ] && return 0
  for login in "${TRUSTED_COMMITTERS[@]}"; do [ "$1" = "$login" ] && return 0; done
  return 1
}

# audit_commit <sha>: a finding line if the commit is neither signed (by a
# trusted committer) nor a keep-alive commit with its status.
audit_commit() {
  local sha=$1 committer problems
  committer=$(verified_committer "$sha") || die "could not read $sha from the GitHub API"
  if [ -n "$committer" ]; then
    is_trusted_committer "$committer" \
      || finding "$sha" "signed and verified, but committed by $committer, not a trusted account"
    return 0
  fi
  problems=$(keepalive_commit_problems "$sha")
  if [ -n "$problems" ]; then
    finding "$sha" "unsigned, and not a keep-alive commit: $(paste -sd ';' - <<<"$problems")"
  elif ! has_keepalive_status "$GH_REPO" "$sha"; then
    finding "$sha" "a keep-alive commit without the $KEEPALIVE_STATUS_CONTEXT status from $GITHUB_ACTIONS_BOT_LOGIN (not pushed by the workflow)"
  fi
}

audit() {
  local entry count=0
  if [ $# -eq 2 ]; then
    [[ "$1" =~ $SHA_REGEX && "$2" =~ $SHA_REGEX ]] || die "the pushed range must be two SHAs"
  elif [ $# -ne 0 ]; then
    die "usage: audit-main-commits.sh audit [<before> <after>]"
  fi
  git cat-file -e "$BASELINE^{commit}" 2>/dev/null \
    || die "the baseline $BASELINE is not in this clone (a shallow checkout? fetch-depth: 0)"
  git merge-base --is-ancestor "$BASELINE" HEAD \
    || die "the baseline $BASELINE is not an ancestor of HEAD: main was rewritten"
  while read -r entry; do
    if [[ "$entry" == '!'* ]]; then
      finding "${entry#!}" "main was rewritten: the push does not contain the previous tip"
      continue
    fi
    audit_commit "$entry"
    count=$((count + 1))
  done < <(commits_to_audit "$@")
  log "audited $count commit(s) after ${BASELINE:0:12}"
}

# issue_body <findings>: the issue's text; the same findings give the same text.
issue_body() {
  printf '%s\n' \
    "The audit of \`main\` (\`scripts/audit-main-commits.sh\`) found commits that are neither signed and verified by a trusted account nor a keep-alive commit pushed by the keep-alive workflow:" \
    "" "| Commit | Author | Why |" "|---|---|---|"
  awk -F'\t' '{printf "| `%s` | %s | %s |\n", $1, $2, $3}' <<<"$1"
  printf '%s\n' "" \
    "**This may mean the keep-alive deploy key leaked**: it is the only credential that can push to \`main\` without a signature. Rotate it now (docs/markDown/engineering/release.md, \"Rotating the keep-alive deploy key\"), look at what each commit changed, revert what is not yours, and check the workflow runs and secrets since. Then move \`AUDIT_BASELINE_COMMIT\` in the script past the reviewed commits; this issue closes on the next clean run."
}

# open_issue_number: the number of the open issue with exactly this title.
open_issue_number() {
  gh issue list --state open --limit 100 --search "in:title \"$ISSUE_TITLE\"" --json number,title \
    | jq -r --arg title "$ISSUE_TITLE" '[.[] | select(.title == $title)][0].number // empty'
}

report() {
  local findings existing body run=${RUN_URL:-}
  findings=$(grep -v '^$' || true)
  existing=$(open_issue_number) || die "could not list the issues"
  if [ -z "$findings" ]; then
    if [ -n "$existing" ]; then
      gh issue close "$existing" --comment "Clean again: every audited commit on main is signed or a keep-alive commit. $run"
      log "closed issue #$existing"
    fi
    log "no finding"
    return 0
  fi
  body=$(issue_body "$findings")
  if [ -z "$existing" ]; then
    gh issue create --title "$ISSUE_TITLE" --body "$body"
  elif [ "$(gh issue view "$existing" --json body | jq -r .body)" != "$body" ]; then
    gh issue edit "$existing" --body "$body"
    gh issue comment "$existing" --body "The findings changed; the list above is updated. $run"
  else
    log "issue #$existing already lists these findings"
  fi
  die "$(grep -c '' <<<"$findings") unexpected commit(s) on main: $(cut -f1 <<<"$findings" | paste -sd ' ' -)"
}

case ${1:-} in
  audit) shift; audit "$@" ;;
  report) [ $# -eq 1 ] || die "usage: audit-main-commits.sh report < findings"; report ;;
  *) die "usage: audit-main-commits.sh audit [<before> <after>] | report" ;;
esac
