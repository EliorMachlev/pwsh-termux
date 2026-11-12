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
# local gpg home and its fingerprint is the one in keys/RECOVERY. It then
# checks the result with verify-recovery-repo.sh.
set -euo pipefail

REPO=${1:?repository folder (build-repo.sh output, unsigned)}
HERE=$(cd "$(dirname "$0")" && pwd)
KEYRING_FILE=${KEYRING_FILE:-$HERE/../keys/pwsh-termux-archive-keyring.gpg}
DIST=$REPO/dists/stable

log() { printf '[recovery-sign] %s\n' "$*" >&2; }
die() { printf '[recovery-sign] ERROR: %s\n' "$*" >&2; exit 1; }

if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  die "the recovery key is offline only: run this on your own machine, never in CI"
fi
recovery=$(bash "$HERE/check-keys.sh" "$KEYRING_FILE" | awk '$2 == "recovery" {print $1}')
[ -n "$recovery" ] || die "no recovery key: keys/RECOVERY is not set up"
secret=$(gpg --batch --list-secret-keys --with-colons -- "$recovery" 2>/dev/null \
  | awk -F: '$1 == "sec" {want = 1; next} $1 == "fpr" && want {print $10; exit}' || true)
[ "$secret" = "$recovery" ] || die "the secret of the recovery key $recovery is not in this gpg home"
[ -f "$DIST/Release" ] || die "$DIST/Release not found (run build-repo.sh first)"

gpgargs=(--batch --yes --local-user "$recovery")
if [ -n "${GPG_PASSPHRASE_FILE:-}" ]; then
  gpgargs+=(--pinentry-mode loopback --passphrase-file "$GPG_PASSPHRASE_FILE")
fi
gpg "${gpgargs[@]}" --clearsign -o "$DIST/InRelease" "$DIST/Release"
gpg "${gpgargs[@]}" -abs -o "$DIST/Release.gpg" "$DIST/Release"

KEYRING_FILE=$KEYRING_FILE bash "$HERE/verify-recovery-repo.sh" "$REPO"
log "signed $REPO with the recovery key $recovery"
