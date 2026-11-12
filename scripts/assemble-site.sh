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
source "$(dirname "$0")/lib/common.sh"

DOCS_DIR=${1:?docs directory}
REPO_DIR=${2:?repo directory (output of build-repo.sh)}

readonly HANDBOOK_SUBDIR=markDown          # docs/markDown stays on GitHub
readonly CACHE_BUSTED_ASSETS=(style.css favicon.svg)
readonly ASSET_HASH_LENGTH=12

# Everything in docs/ except the Markdown handbook.
copy_site() {
  tar -C "$DOCS_DIR" --exclude="./$HANDBOOK_SUBDIR" -cf - . | tar -C "$REPO_DIR" -xf -
}

# stamp_asset <asset>: every page references it as /<asset>?v=<content hash>.
stamp_asset() {
  local asset=$1 hash page
  [ -f "$REPO_DIR/$asset" ] || die "$asset missing from the site"
  hash=$(sha256sum "$REPO_DIR/$asset" | cut -c"1-$ASSET_HASH_LENGTH")
  for page in "$REPO_DIR"/*.html; do
    sed -i "s#\"/$asset\"#\"/$asset?v=$hash\"#g" "$page"
  done
  log "$asset -> ?v=$hash"
}

main() {
  local asset
  [ -f "$DOCS_DIR/index.html" ] || die "$DOCS_DIR/index.html not found"
  [ -d "$REPO_DIR/dists" ] || die "$REPO_DIR is not an apt repository (run build-repo.sh first)"

  copy_site
  shopt -s nullglob
  for asset in "${CACHE_BUSTED_ASSETS[@]}"; do
    stamp_asset "$asset"
  done
  log "site merged into $REPO_DIR"
}

main
