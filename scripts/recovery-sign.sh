#!/usr/bin/env bash
# Sign a repository with the offline RECOVERY key, on the maintainer's own
# machine, after the online key is compromised or lost. apt accepts an index
# that ANY key in the signed-by keyring signs, and every installed keyring
# holds the recovery key, so users can then `pkg upgrade` to a keyring with a
# new online key. The procedure: docs/markDown/engineering/release.md
# ("Recovery with the offline key").
#
# Usage: recovery-sign.sh <repo-dir>
#   <repo-dir> is the output of build-repo.sh run WITHOUT SIGN_KEY, from the
#   current packages and a pwsh-termux-keyring built from the new keys/.
# Env:   KEYRING_FILE  TEST ONLY: instead of keys/pwsh-termux-archive-keyring.gpg
#        GPG_PASSPHRASE_FILE  optional; otherwise gpg asks for the passphrase
#
# It refuses to run in CI, and unless the recovery key's secret is in the
# local gpg home and its fingerprint is the one in keys/RECOVERY, and it
# refuses a Release whose Valid-Until window is unbounded or has fewer than
# VALID_UNTIL_WARN_DAYS (7) days left (build-repo.sh writes 14 from the time
# it runs: build and sign in one sitting). It then checks the result with
# verify-recovery-repo.sh.
#
# The recovery-signed index expires 14 days after build-repo.sh ran, and CI
# cannot re-sign it (it holds no key apt trusts during a recovery), so repeat
# build-repo.sh and this script within every 14 days of a recovery window.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

REPO_DIR=${1:?repository folder (build-repo.sh output, unsigned)}
KEYRING_FILE=${KEYRING_FILE:-$SCRIPTS_DIR/../keys/$KEYRING_BASENAME}
DIST_DIR=$(repo_dist_dir "$REPO_DIR")
readonly DIST_DIR

refuse_in_ci() {
  if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    die "the recovery key is offline only: run this on your own machine, never in CI"
  fi
}

# require_recovery_secret <fingerprint>: its secret is in this gpg home.
require_recovery_secret() {
  local recovery=$1 secret
  secret=$(secret_key_fingerprint "$recovery" 2>/dev/null || true)
  [ "$secret" = "$recovery" ] || die "the secret of the recovery key $recovery is not in this gpg home"
}

# sign_with_recovery_key <fingerprint>: gpg asks for the passphrase unless
# GPG_PASSPHRASE_FILE is set.
sign_with_recovery_key() {
  local -a gpg_options=(--batch --yes --local-user "$1")
  if [ -n "${GPG_PASSPHRASE_FILE:-}" ]; then
    gpg_options+=(--pinentry-mode loopback --passphrase-file "$GPG_PASSPHRASE_FILE")
  fi
  sign_release "$DIST_DIR" "${gpg_options[@]}"
}

main() {
  local recovery
  refuse_in_ci
  recovery=$(require_recovery_fingerprint "$KEYRING_FILE")
  require_recovery_secret "$recovery"
  [ -f "$DIST_DIR/Release" ] || die "$DIST_DIR/Release not found (run build-repo.sh first)"
  check_release_fresh "$DIST_DIR/Release"

  sign_with_recovery_key "$recovery"
  KEYRING_FILE=$KEYRING_FILE bash "$SCRIPTS_DIR/verify-recovery-repo.sh" "$REPO_DIR"
  log "signed $REPO_DIR with the recovery key $recovery"
}

main
