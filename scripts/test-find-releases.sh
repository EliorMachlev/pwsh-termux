#!/usr/bin/env bash
# Tests of find-releases.sh, offline, with a stub `curl` that answers with a
# fixture of the GitHub releases API and records its arguments: the highest
# version wins over the newest date, drafts and releases without the
# linux-arm64 tarball are skipped, the preview is printed only when its core
# version is newer than the stable one, GITHUB_TOKEN is sent as a Bearer
# header (and nothing is sent without it), and a failed or empty answer stops
# the run. Runs on Termux and on CI; touches nothing outside a temporary
# folder.
#
# Usage: test-find-releases.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FIND_RELEASES=$SCRIPTS_DIR/find-releases.sh

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>"$T/err.log"; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    if [ "$got" = refuse ]; then printf '        %s\n' "$(tail -1 "$T/err.log")"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log" "$T/err.log"
  fi
}
# refuse <reason> <description> <command...>: the command fails, for that
# reason (a fixed string in what it printed).
refuse() {
  local reason=$1; shift
  expect refuse "$@"
  if ! grep -qF -- "$reason" "$T/err.log"; then fail "  not for the expected reason: $reason"; fi
}
# expect_output <description> <expected stdout>: what the last run printed.
expect_output() {
  local got
  got=$(cat "$T/out.log")
  if [ "$got" = "$2" ]; then pass "$1"; else fail "$1: got [$got], expected [$2]"; fi
}

# The stub curl: records its arguments, one per line, then prints the
# fixture, or fails as curl -f does on an HTTP error if there is none.
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$STUB_DIR/curl-args"
if [ -f "$STUB_DIR/releases.json" ]; then
  cat "$STUB_DIR/releases.json"
else
  echo "curl: (22) The requested URL returned error: 503" >&2; exit 22
fi
STUB
chmod 755 "$T/bin/curl"
export STUB_DIR=$T PATH="$T/bin:$PATH"
unset GITHUB_TOKEN

# release <tag> <prerelease> [draft] [asset]: one release of the API's list,
# with the linux-arm64 tarball unless another asset is named.
release() {
  local tag=$1 pre=$2 draft=${3:-false} asset=${4:-}
  [ -n "$asset" ] || asset="powershell-${tag#v}-linux-arm64.tar.gz"
  jq -n --arg tag "$tag" --argjson pre "$pre" --argjson draft "$draft" --arg asset "$asset" \
    '{tag_name: $tag, prerelease: $pre, draft: $draft,
      assets: [{name: "hashes.sha256"}, {name: $asset}]}'
}
# releases <release-json...>: the fixture, in the order given (the API's
# order is by date, newest first).
releases() { jq -s . > "$T/releases.json"; }
find_releases() { bash "$FIND_RELEASES"; }

echo "== which releases"
{
  release v7.4.12 false              # a backport, published last
  release v7.6.0-preview.5 true true # a draft
  release v7.6.0-preview.4 true
  release v7.5.3 false
  release v7.5.10 false false powershell-7.5.10-linux-x64.tar.gz   # still uploading
  release v7.5.2 false
} | releases
expect accept "the highest stable and a newer preview" find_releases
expect_output "stable v7.5.3 (not the backport, the draft or the upload)" \
  "$(printf 'stable v7.5.3\npreview v7.6.0-preview.4')"

{
  release v7.5.0 false
  release v7.5.0-rc.1 true
} | releases
expect accept "a preview of the stable version" find_releases
expect_output "no preview line for the same core version" "stable v7.5.0"

{
  release v7.5.1 false
  release v7.5.0-preview.3 true
} | releases
expect accept "an older preview" find_releases
expect_output "no preview line for an older core version" "stable v7.5.1"

{
  release v7.5.1 false
  release v7.10.0-preview.1 true
  release v7.9.0-preview.2 true
} | releases
expect accept "versions compared as versions, not text" find_releases
expect_output "7.10 is newer than 7.9 and 7.5" "$(printf 'stable v7.5.1\npreview v7.10.0-preview.1')"

echo "== the API request"
expect accept "without GITHUB_TOKEN" find_releases
if grep -q '^Authorization' "$T/curl-args"; then
  fail "no Authorization header without GITHUB_TOKEN"
else
  pass "no Authorization header without GITHUB_TOKEN"
fi
expect accept "with GITHUB_TOKEN" env GITHUB_TOKEN=test-token bash "$FIND_RELEASES"
if grep -qxF 'Authorization: Bearer test-token' "$T/curl-args"; then
  pass "the token as a Bearer header"
else
  fail "the token as a Bearer header: $(tr '\n' ' ' < "$T/curl-args")"
fi
if grep -qxF 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=50' "$T/curl-args"; then
  pass "PowerShell's releases API"
else
  fail "PowerShell's releases API: $(tr '\n' ' ' < "$T/curl-args")"
fi

echo "== refusals"
{
  release v7.6.0-preview.4 true
  release v7.5.4 false true
  release v7.5.3 false false powershell-7.5.3-linux-x64.tar.gz
} | releases
refuse 'no stable release found' "no stable release with the tarball" find_releases
echo '[]' > "$T/releases.json"
refuse 'no stable release found' "no release at all" find_releases
rm "$T/releases.json"
refuse 'error: 503' "the API answers with an error" find_releases
if [ -s "$T/out.log" ]; then fail "  printed nothing after the error"; else pass "  printed nothing after the error"; fi

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
