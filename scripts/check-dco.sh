#!/usr/bin/env bash
# The Developer Certificate of Origin (https://developercertificate.org/) on a
# pull request: every commit it adds must carry a Signed-off-by trailer naming
# the commit's author, as `git commit -s` writes it:
#
#   Signed-off-by: Ada Lovelace <ada@example.org>
#
# Checked: each commit in <head> that no <base> has (`git rev-list <head>
# --not <base>...`), in the current git repository. The workflow passes the
# pull request's base commit and the base branch as fetched, so commits that
# reach the branch by merging main in (already on main) are not the pull
# request's and are not checked. The trailer must be in
# the message's trailer block (its last paragraph), as git parses it; the
# name and e-mail address must equal the author's, ignoring case and spaces
# around them. Not checked, and why:
#   merge commits     they join work the other commits bring; GitHub's
#                     "Update branch" makes them, and the squash merge drops them
#   Dependabot's      author dependabot[bot] <49699333+dependabot[bot]@users.
#                     noreply.github.com>, and only in a pull request that
#                     Dependabot opened (<pr-author> is dependabot[bot]): its
#                     own sign-off names support@github.com, not the author
#   the keep-alive    a commit keepalive_commit_problems (lib/common.sh) accepts,
#   commit            byte for byte: the workflow writes it, no person does
#
# Prints one line per commit on stderr; fails, listing the commits without a
# matching sign-off and how to add one, if any lacks it.
#
# Usage: check-dco.sh <pr-author> <head> <base>...
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

readonly DCO_TRAILER=Signed-off-by
readonly DEPENDABOT_LOGIN='dependabot[bot]'
readonly DEPENDABOT_IDENTITY='dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'

[ "$#" -ge 3 ] || die "usage: check-dco.sh <pr-author> <head> <base>..."
pr_author=$1 head=$2
shift 2
bases=("$@")

for rev in "$head" "${bases[@]}"; do
  git rev-parse --verify --quiet "$rev^{commit}" >/dev/null \
    || die "not a commit in this repository: '$rev' (is the history fetched? fetch-depth: 0)"
done

# normalize_identity: stdin's "Name <email>" lines, lower-case, with the
# spaces at either end and around the "<" dropped.
normalize_identity() {
  tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]*</ </'
}

# signed_off_by_author <commit>: true if a Signed-off-by trailer names its author.
signed_off_by_author() {
  local commit=$1 author
  author=$(git show -s --format='%an <%ae>' "$commit" | normalize_identity)
  git show -s --format="%(trailers:key=$DCO_TRAILER,valueonly,unfold)" "$commit" \
    | normalize_identity | grep -qxF -- "$author"
}

checked=0 exempt=0
missing=()
while read -r commit; do
  subject=$(git show -s --format='%h %s' "$commit")
  author=$(git show -s --format='%an <%ae>' "$commit")
  if [ "$author" = "$DEPENDABOT_IDENTITY" ] && [ "$pr_author" = "$DEPENDABOT_LOGIN" ]; then
    log "exempt (Dependabot): $subject"
    exempt=$((exempt + 1))
  elif [ -z "$(keepalive_commit_problems "$commit")" ]; then
    log "exempt (keep-alive commit): $subject"
    exempt=$((exempt + 1))
  elif signed_off_by_author "$commit"; then
    log "signed off: $subject"
    checked=$((checked + 1))
  else
    log "NO SIGN-OFF by $author: $subject"
    missing+=("$subject")
  fi
done < <(git rev-list --no-merges --reverse "$head" --not "${bases[@]}")

if [ "${#missing[@]}" -gt 0 ]; then
  log "Commits without a '$DCO_TRAILER:' trailer naming their author:"
  printf '[%s]   %s\n' "$SCRIPT_NAME" "${missing[@]}" >&2
  log "Sign off each commit (CONTRIBUTING.md, \"Developer Certificate of Origin\"):"
  log "  git rebase --signoff $(git rev-parse --short "${bases[0]}") && git push --force-with-lease"
  die "${#missing[@]} commit(s) not signed off"
fi
log "every commit is signed off ($checked signed off, $exempt exempt)"
