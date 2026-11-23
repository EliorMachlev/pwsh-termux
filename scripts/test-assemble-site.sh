#!/usr/bin/env bash
# Tests of assemble-site.sh, offline, on a small site in a throwaway Git
# repository (two commits with fixed dates) and a hand-written apt index:
# what is copied (not the Markdown handbook), each generated block (status,
# documents, last-updated:<path>) filled from the index and from git log, the
# HTML escaping, the cache-busting ?v=<hash> on the stylesheet and icon, and
# every refusal: no index.html, no apt repository, no Git checkout, a shallow
# clone, a block without its end, a version or index the status cannot show,
# a missing asset, a document missing or not committed. Runs on Termux and
# on CI; touches nothing outside a temporary folder.
#
# Usage: test-assemble-site.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
ASSEMBLE=$SCRIPTS_DIR/assemble-site.sh
# Git as on a clean machine: no user or system configuration (signing, hooks).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

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
# refuse <reason> <description> <command...>: the command fails, for that
# reason (a fixed string in what it printed).
refuse() {
  local reason=$1; shift
  expect refuse "$@"
  if ! grep -qF -- "$reason" "$T/out.log"; then fail "  not for the expected reason: $reason"; fi
}
# has <description> <file> <fixed-string>: the file has that line.
has() { if grep -qxF -- "$3" "$2"; then pass "  $1"; else fail "  $1: no line [$3] in $2"; cat "$2"; fi; }
# lacks <description> <file> <fixed-string>: the file has it nowhere.
lacks() { if grep -qF -- "$3" "$2"; then fail "  $1: [$3] in $2"; else pass "  $1"; fi; }

# block <name> [fallback]: a generated block, as a page marks one.
block() { printf '<!-- generated:%s -->\n<p>%s</p>\n<!-- /generated:%s -->\n' "$1" "${2:-fallback $1}" "$1"; }

# The site's source: two pages, the stylesheet and icon, the handbook, and
# the top-level documents.
O=$T/origin
mkdir -p "$O/docs/markDown"
{
  echo '<!DOCTYPE html>'
  echo '<link rel="stylesheet" href="/style.css"><link rel="icon" href="/favicon.svg">'
  block status
  block documents
  block last-updated:README.md
} > "$O/docs/index.html"
{
  echo '<!DOCTYPE html>'
  echo '<img src="/favicon.svg" alt="">'
  block last-updated:docs/markDown/guide.md
  block last-updated:README.md
} > "$O/docs/other.html"
printf 'body { color: black; }\n' > "$O/docs/style.css"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$O/docs/favicon.svg"
printf '# Guide & <tips>\n\nText.\n' > "$O/docs/markDown/guide.md"
mkdir -p "$O/docs/markDown/product"
printf '# Packages\n' > "$O/docs/markDown/product/packages.md"
printf '<urlset>\n  <url><loc>https://pwsh-termux.machlev.org/</loc></url>\n  <url><loc>https://pwsh-termux.machlev.org/other.html</loc></url>\n</urlset>\n' > "$O/docs/sitemap.xml"
printf 'No heading here.\n' > "$O/docs/markDown/untitled.md"
for doc in README INSTALL SECURITY CONTRIBUTING NOTICE; do printf '# The %s\n' "$doc" > "$O/$doc.md"; done
git -C "$O" init -q
git -C "$O" add -A
GIT_COMMITTER_DATE='2026-01-02T03:04:05Z' git -C "$O" commit -q -m first
printf '# Guide & <tips>\n\nMore text.\n' > "$O/docs/markDown/guide.md"
GIT_COMMITTER_DATE='2026-03-04T05:06:07Z' git -C "$O" commit -q -am second
FIRST=$(git -C "$O" rev-parse HEAD~1)
SECOND=$(git -C "$O" rev-parse HEAD)

# checkout <name>: a full clone of the site's source, to change.
checkout() { git clone -q "$O" "$T/$1"; printf '%s\n' "$T/$1"; }

# index <repo-dir> [<package>=<version>...]: an apt repository with those
# packages (default: pwsh and pwsh-preview), signed 2026-11-14, valid 8 days.
SIGNED=1794614400 VALID=1795305600
index() {
  local repo=$1 dist; shift
  [ "$#" -gt 0 ] || set -- pwsh=7.5.1-1 pwsh-preview=7.6.0~preview.4-1
  dist=$(repo_dist_dir "$repo")
  mkdir -p "$dist/$(repo_index_subdir)"
  for entry in other-package=1.0 "$@"; do
    printf 'Package: %s\nVersion: %s\nArchitecture: aarch64\n\n' "${entry%%=*}" "${entry#*=}"
  done > "$dist/$(repo_index_subdir)/Packages"
  printf 'Origin: t\nDate: %s\nValid-Until: %s\n' "$(release_date "$SIGNED")" "$(release_date "$VALID")" \
    > "$dist/Release"
  printf '%s\n' "$repo"
}
assemble() { bash "$ASSEMBLE" "$@"; }

echo "== the site"
R=$(index "$T/repo")
expect accept "assemble the site into the repository" assemble "$O/docs" "$R"
for f in index.html other.html style.css favicon.svg; do
  if [ -f "$R/$f" ]; then pass "  $f copied"; else fail "  $f copied"; fi
done
has "sitemap.xml: lastmod on the home page" "$R/sitemap.xml" '  <url><loc>https://pwsh-termux.machlev.org/</loc><lastmod>2026-01-02</lastmod></url>'
has "sitemap.xml: lastmod on another page" "$R/sitemap.xml" '  <url><loc>https://pwsh-termux.machlev.org/other.html</loc><lastmod>2026-01-02</lastmod></url>'
has "llms-full.txt joins INSTALL.md" "$R/llms-full.txt" '# The INSTALL'
has "llms-full.txt joins packages.md" "$R/llms-full.txt" '# Packages'
if [ -e "$R/markDown" ]; then fail "  the handbook stays on GitHub"; else pass "  the handbook stays on GitHub"; fi
if [ -d "$R/dists" ]; then pass "  the index is kept"; else fail "  the index is kept"; fi

has "status: the packages served, in order" "$R/index.html" \
  '<p class="status">Now serving <code>pwsh</code> <strong>7.5.1-1</strong> and <code>pwsh-preview</code> <strong>7.6.0~preview.4-1</strong>. Repository index last signed <time datetime="2026-11-14T00:00Z">2026-11-14 00:00 UTC</time>, valid until <time datetime="2026-11-22T00:00Z">2026-11-22</time> (it is re-signed daily).</p>'
lacks "the fallback HTML is replaced" "$R/index.html" 'fallback'
has "the markers stay" "$R/index.html" '<!-- generated:status -->'
has "  ... both of them" "$R/index.html" '<!-- /generated:status -->'

BLOB=https://github.com/EliorMachlev/pwsh-termux/blob/main
COMMIT=https://github.com/EliorMachlev/pwsh-termux/commit
has "documents: the handbook first, the title HTML-escaped, its last commit" "$R/index.html" \
  "    <tr><td><a href=\"$BLOB/docs/markDown/guide.md\">Guide &amp; &lt;tips&gt;</a><br><code>docs/markDown/guide.md</code></td><td>Last updated <time datetime=\"2026-03-04\">2026-03-04</time> &middot; <a href=\"$COMMIT/$SECOND\"><code>${SECOND:0:7}</code></a></td></tr>"
has "  a document without a heading is listed by its path" "$R/index.html" \
  "    <tr><td><a href=\"$BLOB/docs/markDown/untitled.md\">docs/markDown/untitled.md</a><br><code>docs/markDown/untitled.md</code></td><td>Last updated <time datetime=\"2026-01-02\">2026-01-02</time> &middot; <a href=\"$COMMIT/$FIRST\"><code>${FIRST:0:7}</code></a></td></tr>"
same_order=$(grep -o '<code>[A-Za-z/]*\.md</code>' "$R/index.html" | tr '\n' ' ')
if [ "$same_order" = "<code>docs/markDown/guide.md</code> <code>docs/markDown/product/packages.md</code> <code>docs/markDown/untitled.md</code> <code>README.md</code> <code>INSTALL.md</code> <code>SECURITY.md</code> <code>CONTRIBUTING.md</code> <code>NOTICE.md</code> " ]; then
  pass "  then the top-level documents, in order"
else
  fail "  then the top-level documents, in order: $same_order"
fi

has "last-updated: README.md" "$R/index.html" \
  "<p class=\"updated\">Last updated <time datetime=\"2026-01-02\">2026-01-02</time> &middot; <a href=\"$COMMIT/$FIRST\"><code>${FIRST:0:7}</code></a></p>"
has "  in every page that has the block" "$R/other.html" \
  "<p class=\"updated\">Last updated <time datetime=\"2026-01-02\">2026-01-02</time> &middot; <a href=\"$COMMIT/$FIRST\"><code>${FIRST:0:7}</code></a></p>"
has "  and a handbook document's own block" "$R/other.html" \
  "<p class=\"updated\">Last updated <time datetime=\"2026-03-04\">2026-03-04</time> &middot; <a href=\"$COMMIT/$SECOND\"><code>${SECOND:0:7}</code></a></p>"
lacks "  a page without a block is left alone" "$R/other.html" 'Now serving'

CSS=$(sha256_of "$O/docs/style.css") ICON=$(sha256_of "$O/docs/favicon.svg")
has "the stylesheet and icon carry their content hash" "$R/index.html" \
  "<link rel=\"stylesheet\" href=\"/style.css?v=${CSS:0:12}\"><link rel=\"icon\" href=\"/favicon.svg?v=${ICON:0:12}\">"
has "  in every page" "$R/other.html" "<img src=\"/favicon.svg?v=${ICON:0:12}\" alt=\"\">"

R=$(index "$T/repo-stable" pwsh=7.5.1-1)
expect accept "an index with pwsh only" assemble "$O/docs" "$R"
if grep -qF 'Now serving <code>pwsh</code> <strong>7.5.1-1</strong>. Repository' "$R/index.html"; then
  pass "  names pwsh only"
else
  fail "  names pwsh only"
fi
R=$(index "$T/repo-preview" pwsh-preview=7.6.0~rc.1-1)
expect accept "an index with pwsh-preview only" assemble "$O/docs" "$R"
if grep -qF 'Now serving <code>pwsh-preview</code> <strong>7.6.0~rc.1-1</strong>. Repository' "$R/index.html"; then
  pass "  names pwsh-preview only"
else
  fail "  names pwsh-preview only"
fi

echo "== refusals"
mkdir -p "$T/no-index"
refuse 'index.html not found' "a docs folder without index.html" assemble "$T/no-index" "$(index "$T/r1")"
mkdir -p "$T/not-a-repo"
refuse 'is not an apt repository' "a folder that is not an apt repository" assemble "$O/docs" "$T/not-a-repo"
cp -r "$O/docs" "$T/no-git"
refuse 'is not in a Git checkout' "docs outside a Git checkout" assemble "$T/no-git" "$(index "$T/r2")"
git clone -q --depth 1 "file://$O" "$T/shallow"
refuse 'is a shallow clone' "a shallow clone" assemble "$T/shallow/docs" "$(index "$T/r3")"

C=$(checkout no-end)
printf '<!-- generated:status -->\n' > "$C/docs/broken.html"
refuse "has no generated block 'status'" "a block without its end" assemble "$C/docs" "$(index "$T/r4")"
refuse "unexpected version for pwsh" "a version build-deb.sh would not write" \
  assemble "$O/docs" "$(index "$T/r5" 'pwsh=7.5.1<b>')"
R=$(index "$T/r6" other=1.0)
refuse 'serves none of pwsh pwsh-preview' "an index without pwsh or pwsh-preview" assemble "$O/docs" "$R"
R=$(index "$T/r7")
printf 'Origin: t\nDate: %s\n' "$(release_date "$SIGNED")" > "$(repo_dist_dir "$R")/Release"
refuse 'has no Valid-Until' "a Release without Valid-Until" assemble "$O/docs" "$R"
R=$(index "$T/r8")
rm "$(repo_dist_dir "$R")/Release"
refuse 'has no Packages or Release' "an index without Release" assemble "$O/docs" "$R"
C=$(checkout no-icon)
git -C "$C" rm -q docs/favicon.svg
refuse 'favicon.svg missing from the site' "no favicon.svg" assemble "$C/docs" "$(index "$T/r9")"
C=$(checkout no-readme)
rm "$C/README.md"
refuse 'README.md not found' "a top-level document that is not there" assemble "$C/docs" "$(index "$T/r10")"
C=$(checkout bad-block)
block last-updated:CHANGES.md > "$C/docs/changes.html"
git -C "$C" add docs/changes.html
git -C "$C" commit -q -m 'a page'
refuse 'CHANGES.md not found' "a last-updated block for a file that is not there" assemble "$C/docs" "$(index "$T/r12")"
C=$(checkout uncommitted)
printf '# New\n' > "$C/docs/markDown/new.md"
refuse 'docs/markDown/new.md has no commit' "a handbook document not committed yet" assemble "$C/docs" "$(index "$T/r11")"

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
