#!/usr/bin/env bash
# Merge the website into the apt repository tree, ready to deploy.
#
# Usage: assemble-site.sh <docs-dir> <repo-dir>
#
# - copies everything in docs/ except the Markdown handbook (docs/markDown,
#   which lives on GitHub, not on the site);
# - fills each generated block in the pages from the repository it is merged
#   into (below);
# - stamps every local stylesheet/icon reference as name?v=<content hash>, so a
#   deploy never pairs a new page with a stylesheet a browser still has cached
#   (GitHub Pages lets browsers keep assets for hours but pages for minutes).
#
# Generated blocks. A page marks one with two comment lines,
#   <!-- generated:<name> -->
#   ...fallback HTML, shown as it is when docs/ is opened without this step...
#   <!-- /generated:<name> -->
# and this replaces the lines between them:
#   status   the packages the index serves, with their versions, and the
#            index's Date and Valid-Until (from Packages and Release).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

DOCS_DIR=${1:?docs directory}
REPO_DIR=${2:?repo directory (output of build-repo.sh)}

readonly HANDBOOK_SUBDIR=markDown          # docs/markDown stays on GitHub
readonly CACHE_BUSTED_ASSETS=(style.css favicon.svg)
readonly ASSET_HASH_LENGTH=12
# The packages the status block names, in this order, when the index has them.
readonly STATUS_PACKAGES=(pwsh pwsh-preview)
# A Debian version as build-deb.sh writes it; anything else is not put in a page.
readonly DEB_VERSION_REGEX='^[0-9][0-9A-Za-z.+~-]*$'

# Removed on exit.
WORK_DIR=

# Everything in docs/ except the Markdown handbook.
copy_site() {
  tar -C "$DOCS_DIR" --exclude="./$HANDBOOK_SUBDIR" -cf - . | tar -C "$REPO_DIR" -xf -
}

# fill_block <page> <name> <html-file>: replace the generated block <name>
# in the page with the file's content. Dies if the page has no such block.
fill_block() {
  local page=$1 name=$2 html_file=$3 begin end
  begin="<!-- generated:$name -->" end="<!-- /generated:$name -->"
  if ! grep -qxF -- "$begin" "$page" || ! grep -qxF -- "$end" "$page"; then
    die "$page has no generated block '$name'"
  fi
  awk -v begin="$begin" -v end="$end" -v html_file="$html_file" '
    $0 == begin { print; while ((getline line < html_file) > 0) print line; skip = 1; next }
    $0 == end   { skip = 0 }
    !skip       { print }' "$page" > "$page.new"
  mv "$page.new" "$page"
}

# fill_blocks <name> <html-file>: fill the block in every page that has it.
fill_blocks() {
  local name=$1 html_file=$2 page filled=0
  for page in "$REPO_DIR"/*.html; do
    if grep -qxF -- "<!-- generated:$name -->" "$page"; then
      fill_block "$page" "$name" "$html_file"
      filled=$((filled + 1))
    fi
  done
  log "generated:$name -> $filled page(s)"
}

# package_version <packages-file> <package>: its Version in the index, or nothing.
package_version() {
  awk -v want="$2" '
    /^Package: / {pkg = $2} /^Version: / && pkg == want {print $2; exit}' "$1"
}

# write_status <out-file>: the status block, from the repository's index.
write_status() {
  local out=$1 dist_dir packages_file release_file package version served=() date valid_until
  dist_dir=$(repo_dist_dir "$REPO_DIR")
  packages_file=$dist_dir/$(repo_index_subdir)/Packages
  release_file=$dist_dir/Release
  [ -f "$packages_file" ] && [ -f "$release_file" ] || die "$REPO_DIR has no Packages or Release"
  for package in "${STATUS_PACKAGES[@]}"; do
    version=$(package_version "$packages_file" "$package")
    [ -n "$version" ] || continue
    [[ "$version" =~ $DEB_VERSION_REGEX ]] || die "unexpected version for $package: '$version'"
    served+=("<code>$package</code> <strong>$version</strong>")
  done
  [ "${#served[@]}" -gt 0 ] || die "the index serves none of ${STATUS_PACKAGES[*]}"
  date=$(release_field_epoch "$release_file" Date)
  valid_until=$(release_field_epoch "$release_file" Valid-Until)
  {
    printf '<p class="status">Now serving %s.' "$(join_with ' and ' "${served[@]}")"
    printf ' Repository index last signed <time datetime="%s">%s</time>,' \
      "$(date -u -d "@$date" +%Y-%m-%dT%H:%MZ)" "$(date -u -d "@$date" '+%Y-%m-%d %H:%M UTC')"
    printf ' valid until <time datetime="%s">%s</time> (it is re-signed daily).</p>\n' \
      "$(date -u -d "@$valid_until" +%Y-%m-%dT%H:%MZ)" "$(date -u -d "@$valid_until" '+%Y-%m-%d')"
  } > "$out"
}

# join_with <separator> <item...>
join_with() {
  local separator=$1 joined=$2; shift 2
  local item
  for item in "$@"; do joined+="$separator$item"; done
  printf '%s\n' "$joined"
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
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT

  copy_site
  shopt -s nullglob
  write_status "$WORK_DIR/status.html"
  fill_blocks status "$WORK_DIR/status.html"
  for asset in "${CACHE_BUSTED_ASSETS[@]}"; do
    stamp_asset "$asset"
  done
  log "site merged into $REPO_DIR"
}

main
