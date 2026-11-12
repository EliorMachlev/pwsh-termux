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
#   documents          a table of every Markdown document (the handbook in
#                      docs/markDown and the top-level ones), each with
#                      "Last updated <date> · <short sha>" linked to its commit.
#   last-updated:<path>  that line for one Markdown file (path from the
#                      repository root).
# The dates and commits come from `git log -1` for each file, so they cannot
# go stale and no file holds its own date. That needs the full Git history:
# it stops with an error in a shallow clone (actions/checkout needs
# fetch-depth: 0) or outside a Git checkout, rather than print a wrong date.
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
# The Markdown documents the documents block lists, besides docs/markDown.
readonly TOP_LEVEL_DOCUMENTS=(README.md SECURITY.md CONTRIBUTING.md NOTICE.md)
readonly LAST_UPDATED_BLOCK_PREFIX=last-updated:

# Set by require_full_history: the Git checkout docs/ is in, and docs/'s
# path in it ("docs/").
GIT_TOP=
DOCS_PREFIX=

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

# html_escape: stdin to stdout, with & < > " escaped.
html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# require_full_history: docs/ is in a Git checkout with its whole history;
# sets GIT_TOP. In a shallow clone `git log -1 -- <file>` would name the
# shallow tip for every file, a wrong answer that looks right.
require_full_history() {
  GIT_TOP=$(git -C "$DOCS_DIR" rev-parse --show-toplevel 2>/dev/null) \
    || die "$DOCS_DIR is not in a Git checkout: the documents' dates and commits come from git log"
  DOCS_PREFIX=$(git -C "$DOCS_DIR" rev-parse --show-prefix)
  [ "$(git -C "$GIT_TOP" rev-parse --is-shallow-repository)" = false ] \
    || die "$GIT_TOP is a shallow clone: fetch the full history (actions/checkout with fetch-depth: 0, or git fetch --unshallow)"
}

# last_commit <path>: "<date> <short-sha> <sha>" of the last commit that
# changed the file (path from the repository root). Dies if there is none.
last_commit() {
  local path=$1 commit
  [ -f "$GIT_TOP/$path" ] || die "$path not found"
  commit=$(git -C "$GIT_TOP" log -1 --format='%cs %h %H' -- "$path")
  [ -n "$commit" ] || die "$path has no commit in the Git history (not committed yet?)"
  printf '%s\n' "$commit"
}

# last_updated_html <path>: "Last updated <date> · <short sha>", linked to the commit.
last_updated_html() {
  local date short sha
  read -r date short sha < <(last_commit "$1") || die "no commit for $1"
  printf 'Last updated <time datetime="%s">%s</time> &middot; <a href="%s"><code>%s</code></a>' \
    "$date" "$date" "$(project_commit_url "$sha")" "$short"
}

# document_title <path>: its first "# " heading, HTML-escaped, or the path.
document_title() {
  local title
  title=$(awk '/^# / {sub(/^# +/, ""); print; exit}' "$GIT_TOP/$1")
  printf '%s\n' "${title:-$1}" | html_escape
}

# markdown_documents: the paths the documents block lists, handbook first.
markdown_documents() {
  ( cd "$GIT_TOP" && find "$DOCS_PREFIX$HANDBOOK_SUBDIR" -name '*.md' -type f | LC_ALL=C sort )
  printf '%s\n' "${TOP_LEVEL_DOCUMENTS[@]}"
}

# write_documents <out-file>: the documents table.
write_documents() {
  local out=$1 path
  {
    echo '<table>'
    echo '  <thead><tr><th>Document</th><th>Last change</th></tr></thead>'
    echo '  <tbody>'
    while read -r path; do
      printf '    <tr><td><a href="%s">%s</a><br><code>%s</code></td><td>%s</td></tr>\n' \
        "$(project_blob_url "$path")" "$(document_title "$path")" "$path" "$(last_updated_html "$path")"
    done < <(markdown_documents)
    echo '  </tbody>'
    echo '</table>'
  } > "$out"
}

# fill_last_updated_blocks: each last-updated:<path> block in the pages.
fill_last_updated_blocks() {
  local name path html_file
  while read -r name; do
    path=${name#"$LAST_UPDATED_BLOCK_PREFIX"}
    html_file=$WORK_DIR/last-updated-$(sha256sum <<<"$path" | cut -c1-16).html
    printf '<p class="updated">%s</p>\n' "$(last_updated_html "$path")" > "$html_file"
    fill_blocks "$name" "$html_file"
  done < <(sed -n "s#^<!-- generated:\(${LAST_UPDATED_BLOCK_PREFIX}[^ ]*\) -->\$#\1#p" "$REPO_DIR"/*.html | sort -u)
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

  require_full_history
  copy_site
  shopt -s nullglob
  write_documents "$WORK_DIR/documents.html"
  fill_blocks documents "$WORK_DIR/documents.html"
  fill_last_updated_blocks
  write_status "$WORK_DIR/status.html"
  fill_blocks status "$WORK_DIR/status.html"
  for asset in "${CACHE_BUSTED_ASSETS[@]}"; do
    stamp_asset "$asset"
  done
  log "site merged into $REPO_DIR"
}

main
