#!/usr/bin/env bash
# Verify a repository signed with the offline RECOVERY key (recovery-sign.sh)
# before it is deployed: used by recovery-sign.sh on the maintainer's machine
# and by .github/workflows/recover.yaml, which has no signing key at all.
#
# Usage: verify-recovery-repo.sh <repo-dir>
# Env:   KEYRING_FILE  TEST ONLY: instead of keys/pwsh-termux-archive-keyring.gpg
#
# Fails unless:
#   - keys/ passes check-keys.sh and keys/RECOVERY names a recovery key;
#   - InRelease and Release.gpg verify with gpgv against the recovery key
#     ALONE, and InRelease's signed text is the Release file;
#   - every index file's SHA-256 matches Release, every .deb in pool/ is
#     listed in Packages with a matching SHA-256, and nothing else is in pool/;
#   - pwsh-termux.gpg is keys/pwsh-termux-archive-keyring.gpg byte for byte,
#     and pwsh-termux-keyring.deb is listed in Packages and ships that file.
set -euo pipefail

REPO=${1:?repository folder}
HERE=$(cd "$(dirname "$0")" && pwd)
KEYRING_FILE=${KEYRING_FILE:-$HERE/../keys/pwsh-termux-archive-keyring.gpg}
KEYRING_MEMBER=./data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg
DIST=$REPO/dists/stable

log() { printf '[verify-recovery-repo] %s\n' "$*" >&2; }
die() { printf '[verify-recovery-repo] ERROR: %s\n' "$*" >&2; exit 1; }

recovery=$(bash "$HERE/check-keys.sh" "$KEYRING_FILE" | awk '$2 == "recovery" {print $1}')
[ -n "$recovery" ] || die "no recovery key: keys/RECOVERY is not set up"
for f in "$DIST/Release" "$DIST/InRelease" "$DIST/Release.gpg" "$REPO/pwsh-termux.gpg" "$REPO/pwsh-termux-keyring.deb"; do
  [ -f "$f" ] && [ ! -L "$f" ] || die "missing or not a regular file: $f"
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A keyring with the recovery key only.
mkdir -m 700 "$work/gnupg"
gpg --batch --homedir "$work/gnupg" --import "$KEYRING_FILE" 2>/dev/null
gpg --batch --homedir "$work/gnupg" --export -- "$recovery" > "$work/recovery.gpg"
[ -s "$work/recovery.gpg" ] || die "could not export the recovery key $recovery"

gpgv --keyring "$work/recovery.gpg" --output - "$DIST/InRelease" 2>/dev/null > "$work/inrelease.txt" \
  || die "InRelease is not signed by the recovery key $recovery"
gpgv --keyring "$work/recovery.gpg" "$DIST/Release.gpg" "$DIST/Release" 2>/dev/null \
  || die "Release.gpg is not a signature of Release by the recovery key $recovery"
cmp -s "$work/inrelease.txt" "$DIST/Release" || die "InRelease does not sign the same text as Release"

# Release -> index files.
listed=0
while read -r sha size path; do
  f="$DIST/$path"
  [ -f "$f" ] || die "Release lists $path, which is missing"
  [ "$(sha256sum < "$f" | cut -d' ' -f1)" = "$sha" ] && [ "$(stat -c %s "$f")" = "$size" ] \
    || die "$path does not match Release"
  listed=$((listed + 1))
done < <(awk '/^SHA256:/ {on = 1; next} /^[^ ]/ {on = 0} on {print $1, $2, $3}' "$DIST/Release")
[ "$listed" -gt 0 ] || die "Release lists no index files"
packages="$DIST/main/binary-aarch64/Packages"
grep -q " main/binary-aarch64/Packages$" "$DIST/Release" || die "Release does not list $packages"

# Packages -> every .deb in pool/, and nothing else.
awk '/^Filename: / {f = $2} /^SHA256: / {print f, $2}' "$packages" > "$work/debs.txt"
while read -r rel sha; do
  [ -f "$REPO/$rel" ] || die "Packages lists $rel, which is missing"
  [ "$(sha256sum < "$REPO/$rel" | cut -d' ' -f1)" = "$sha" ] || die "$rel does not match Packages"
done < "$work/debs.txt"
( cd "$REPO" && find pool -type f -o -type l ) | sort > "$work/pool.txt"
cut -d' ' -f1 "$work/debs.txt" | sort > "$work/listed.txt"
cmp -s "$work/pool.txt" "$work/listed.txt" || die "pool/ holds files that Packages does not list"

# The key files.
cmp -s "$REPO/pwsh-termux.gpg" "$KEYRING_FILE" || die "pwsh-termux.gpg is not $KEYRING_FILE"
keyring_sha=$(sha256sum < "$REPO/pwsh-termux-keyring.deb" | cut -d' ' -f1)
cut -d' ' -f2 "$work/debs.txt" | grep -qx "$keyring_sha" \
  || die "pwsh-termux-keyring.deb is not a package listed in Packages"
dpkg-deb --fsys-tarfile "$REPO/pwsh-termux-keyring.deb" | tar -xOf - "$KEYRING_MEMBER" | cmp -s - "$KEYRING_FILE" \
  || die "pwsh-termux-keyring.deb does not ship $KEYRING_FILE"

log "signed by the recovery key $recovery; index, pool and key files consistent"
