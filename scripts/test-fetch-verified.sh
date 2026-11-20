#!/usr/bin/env bash
# Tests of fetch-verified.sh and the shared download in lib/common.sh,
# offline, with a stub curl: a file with the right SHA-256 is kept, one with
# the wrong hash is refused, a copy that already matches is not downloaded
# again, a stale or wrong copy is replaced, a failing download fails, every
# error is retried, and the arguments are required. Touches nothing outside a
# temporary folder.
#
# Usage: test-fetch-verified.sh
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FETCH=$SCRIPTS_DIR/fetch-verified.sh

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" > "$T/out.log" 2>&1; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what ($got)"
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log"
  fi
}
# check <description> <command...>: the command succeeds.
check() {
  local what=$1; shift
  if "$@"; then pass "  $what"; else fail "  $what"; fi
}

mkdir -p "$T/bin"
# The stub curl: writes the payload to -o's file (or fails when asked to) and
# records its arguments.
cat > "$T/bin/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/curl.log"
out=
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; shift; fi
  shift
done
if [ -e "$STUB_DIR/curl-fails" ]; then echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; fi
printf 'payload\n' > "$out"
STUB
chmod 755 "$T/bin/curl"
export STUB_DIR=$T PATH="$T/bin:$PATH"

GOOD=$(printf 'payload\n' | sha256sum | cut -d' ' -f1)
BAD=$(printf 'other\n' | sha256sum | cut -d' ' -f1)
URL=https://example.invalid/tool

echo "== download and hash"
expect accept "the right hash is kept" bash "$FETCH" "$URL" "$GOOD" "$T/tool"
check "the file is there" test -f "$T/tool"
check "curl retries every error, $DOWNLOAD_RETRIES times" grep -q -- "--retry $DOWNLOAD_RETRIES .*--retry-all-errors" "$T/curl.log"
check "the URL is passed" grep -qF "$URL" "$T/curl.log"
expect refuse "a wrong hash is refused" bash "$FETCH" "$URL" "$BAD" "$T/tool2"

echo "== a copy that is already there"
: > "$T/curl.log"
expect accept "a matching copy is kept" bash "$FETCH" "$URL" "$GOOD" "$T/tool"
check "nothing was downloaded" test ! -s "$T/curl.log"
echo stale > "$T/tool"
expect accept "a non-matching copy is replaced" bash "$FETCH" "$URL" "$GOOD" "$T/tool"
check "it was downloaded again" test -s "$T/curl.log"

echo "== failures"
touch "$T/curl-fails"
expect refuse "a failing download fails" bash "$FETCH" "$URL" "$GOOD" "$T/tool3"
rm "$T/curl-fails"
expect refuse "no arguments" bash "$FETCH"
expect refuse "two arguments" bash "$FETCH" "$URL" "$GOOD"

if [ "$fails" -ne 0 ]; then echo "$fails FAILED" >&2; exit 1; fi
echo "all passed"
