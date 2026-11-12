#!/usr/bin/env bash
# Merge the website into the apt repository tree, ready to deploy.
#
# Usage: assemble-site.sh <docs-dir> <repo-dir>
#
# - copies everything in docs/ except the Markdown handbook (docs/markDown,
#   which lives on GitHub, not on the site);
# - stamps every local stylesheet/icon reference as name?v=<content hash>, so a
#   deploy never pairs a new page with a stylesheet a browser still has cached
#   (GitHub Pages lets browsers keep assets for hours but pages for minutes).
set -euo pipefail

DOCS=${1:?docs directory}
REPO=${2:?repo directory (output of build-repo.sh)}

log() { printf '[assemble-site] %s\n' "$*" >&2; }
die() { printf '[assemble-site] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$DOCS/index.html" ] || die "$DOCS/index.html not found"
[ -d "$REPO/dists" ] || die "$REPO is not an apt repository (run build-repo.sh first)"

tar -C "$DOCS" --exclude=./markDown -cf - . | tar -C "$REPO" -xf -

shopt -s nullglob
for asset in style.css favicon.svg; do
  [ -f "$REPO/$asset" ] || die "$asset missing from the site"
  hash=$(sha256sum "$REPO/$asset" | cut -c1-12)
  for page in "$REPO"/*.html; do
    sed -i "s#\"/$asset\"#\"/$asset?v=$hash\"#g" "$page"
  done
  log "$asset -> ?v=$hash"
done
log "site merged into $REPO"
