#!/usr/bin/env bash
# Check a published InRelease: signed by a key in keys/ (as apt checks it),
# and with at least VALID_UNTIL_WARN_DAYS (7) days left before its
# Valid-Until (scripts/lib/common.sh). Used by .github/workflows/staleness.yaml
# on the live https://pwsh-termux.machlev.org/dists/stable/InRelease.
#
# Usage: check-index-freshness.sh <InRelease-file>
# Env:   KEYRING_FILE  TEST ONLY: instead of keys/pwsh-termux-archive-keyring.gpg
#
# Prints "valid until <date> (<n> days left)" on stdout and exits 0, or dies
# with the reason. Only the signed text is read, never what is around it.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

IN_RELEASE=${1:?InRelease file}
KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}

# Removed on exit.
WORK_DIR=

main() {
  local signed_text
  [ -f "$IN_RELEASE" ] || die "$IN_RELEASE not found"
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  signed_text=$WORK_DIR/Release
  gpgv_quiet "$(realpath "$KEYRING_FILE")" --output - "$IN_RELEASE" > "$signed_text" \
    || die "InRelease does not verify against $KEYRING_FILE"
  check_release_fresh "$signed_text"
  printf 'valid until %s (%s days left)\n' \
    "$(release_field "$signed_text" Valid-Until)" "$(release_days_left "$signed_text")"
}

main
