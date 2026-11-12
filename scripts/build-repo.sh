#!/usr/bin/env bash
# Assemble a signed apt repository from .deb files.
#
# Usage: build-repo.sh <debs-dir> <repo-dir>
# Env:   SIGN_KEY   gpg key id/fingerprint to sign with. If unset the repo is
#                   left UNSIGNED (fine for local tests, not for publishing).
#        GPG_PASSPHRASE_FILE  optional passphrase file for the signing key
#        KEYRING_FILE  TEST ONLY: the public keyring to check against and
#                   publish instead of keys/pwsh-termux-archive-keyring.gpg
#                   (for a throwaway key; see docs/markDown/engineering/build.md).
#
# When signing, it fails closed unless all of these hold:
#   - the debs folder holds one pwsh-termux-keyring package (in CI: the one
#     the unprivileged build job built and attested) that ships exactly the
#     keyring file;
#   - build-keyring.sh, run again here from the same keyring file and the same
#     SOURCE_DATE_EPOCH, gives that package byte for byte (the attested build
#     is reproducible, and nothing else went into it);
#   - the public key exported from SIGN_KEY itself is in the keyring the
#     package ships (and in the keyring file);
#   - the signed index verifies against the keyring file with gpgv, as apt will.
# The package from the debs folder is what gets published, never the rebuild,
# so its attestation verifies on the shipped file.
#
# Layout (suite "stable", component "main", arch "aarch64"):
#   repo/pool/main/<pkg>/*.deb
#   repo/dists/stable/{Release,InRelease,Release.gpg}
#   repo/dists/stable/main/binary-aarch64/Packages{,.gz,.xz}
#   repo/pwsh-termux.gpg  pwsh-termux.asc   (the keyring file, binary and armored)
#   repo/pwsh-termux-keyring.deb            (the keyring package under a fixed name)
# The website is merged in afterwards by assemble-site.sh.
set -euo pipefail

DEBS=${1:?debs directory}
REPO=${2:?repo output directory}
SUITE=stable COMP=main ARCH=aarch64
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
KEYRING_FILE=${KEYRING_FILE:-$ROOT/keys/pwsh-termux-archive-keyring.gpg}
KEYRING_MEMBER=./data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg

log() { printf '[build-repo] %s\n' "$*" >&2; }
die() { printf '[build-repo] ERROR: %s\n' "$*" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

shopt -s nullglob
debs=("$DEBS"/*.deb)
[ "${#debs[@]}" -gt 0 ] || die "no .deb files in $DEBS"
keyring_debs=("$DEBS"/pwsh-termux-keyring_*.deb)
[ "${#keyring_debs[@]}" -le 1 ] || die "more than one pwsh-termux-keyring package in $DEBS"

# The keyring file holds public keys only, and its fingerprints are the ones
# the repository may be signed with.
key_fprs=$(bash "$HERE/check-keys.sh" "$KEYRING_FILE" | cut -d' ' -f1)

# The keyring package, when present, must ship exactly the keyring file.
if [ "${#keyring_debs[@]}" -eq 1 ]; then
  dpkg-deb --fsys-tarfile "${keyring_debs[0]}" | tar -xOf - "$KEYRING_MEMBER" | cmp -s - "$KEYRING_FILE" \
    || die "${keyring_debs[0]} does not ship $KEYRING_FILE"
fi

if [ -n "${SIGN_KEY:-}" ]; then
  [ "${#keyring_debs[@]}" -eq 1 ] || die "signing, but $DEBS has no pwsh-termux-keyring package (build-keyring.sh)"
  sign_fpr=$(gpg --batch --list-secret-keys --with-colons -- "$SIGN_KEY" \
    | awk -F: '$1 == "sec" {want = 1; next} $1 == "fpr" && want {print $10; exit}')
  [ -n "$sign_fpr" ] || die "no secret key for SIGN_KEY in the keyring"
  grep -qx "$sign_fpr" <<<"$key_fprs" \
    || die "the signing key $sign_fpr is not in $KEYRING_FILE; add its public key there first (release.md, rotating the signing key)"

  # Rebuild the keyring package here and require the same bytes. Not a package
  # built from the exported signing key alone: during a planned rotation keys/
  # also holds the next key, so that would differ by design.
  rebuilt=$(KEYRING_FILE="$KEYRING_FILE" bash "$HERE/build-keyring.sh" "$work/rebuild")
  cmp -s "$rebuilt" "${keyring_debs[0]}" \
    || die "${keyring_debs[0]} is not what build-keyring.sh builds from $KEYRING_FILE (sha256 $(sha256sum < "${keyring_debs[0]}" | cut -d' ' -f1) vs $(sha256sum < "$rebuilt" | cut -d' ' -f1))"

  # The public half of the key that will sign, exported from it (public only),
  # must be in the keyring the package installs.
  gpg --batch --export -- "$sign_fpr" > "$work/signing-public.gpg"
  exported_fpr=$(gpg --batch --show-keys --with-colons "$work/signing-public.gpg" \
    | awk -F: '$1 == "pub" {want = 1; next} $1 == "fpr" && want {print $10; exit}')
  [ "$exported_fpr" = "$sign_fpr" ] || die "could not export the public half of $sign_fpr"
  dpkg-deb --fsys-tarfile "${keyring_debs[0]}" | tar -xOf - "$KEYRING_MEMBER" > "$work/packaged.gpg"
  gpg --batch --show-keys --with-colons "$work/packaged.gpg" \
    | awk -F: '$1 == "pub" {want = 1; next} $1 == "fpr" && want {print $10; want = 0}' \
    | grep -qx "$exported_fpr" \
    || die "the signing key $exported_fpr is not in the keyring that ${keyring_debs[0]} installs"
  log "keyring package reproduced byte for byte and holds the signing key $sign_fpr"
fi

rm -rf "$REPO"
mkdir -p "$REPO"

# The published key files are the keyring file itself, so the manual install
# and the package trust the same keys.
cp "$KEYRING_FILE" "$REPO/pwsh-termux.gpg"
gpg --batch --no-default-keyring --import-options import-export --armor \
  --import "$KEYRING_FILE" > "$REPO/pwsh-termux.asc" 2>/dev/null
gpg --batch --dearmor < "$REPO/pwsh-termux.asc" | cmp -s - "$REPO/pwsh-termux.gpg" \
  || die "pwsh-termux.asc is not the armored pwsh-termux.gpg"
if [ "${#keyring_debs[@]}" -eq 1 ]; then
  cp "${keyring_debs[0]}" "$REPO/pwsh-termux-keyring.deb"   # a fixed name for the install line
fi

bindir="$REPO/dists/$SUITE/$COMP/binary-$ARCH"
mkdir -p "$bindir"

: > "$bindir/Packages"
for deb in "${debs[@]}"; do
  pkg=$(dpkg-deb -f "$deb" Package)
  mkdir -p "$REPO/pool/$COMP/$pkg"
  cp "$deb" "$REPO/pool/$COMP/$pkg/"
  rel="pool/$COMP/$pkg/$(basename "$deb")"
  {
    dpkg-deb -f "$deb"
    echo "Filename: $rel"
    echo "Size: $(stat -c %s "$deb")"
    echo "MD5sum: $(md5sum "$deb" | cut -d' ' -f1)"
    echo "SHA256: $(sha256sum "$deb" | cut -d' ' -f1)"
    echo
  } >> "$bindir/Packages"
done
gzip -9kn "$bindir/Packages"
command -v xz >/dev/null && xz -9ke "$bindir/Packages"

rel="$REPO/dists/$SUITE/Release"
{
  echo "Origin: pwsh-termux"
  echo "Label: pwsh-termux"
  echo "Suite: $SUITE"
  echo "Codename: $SUITE"
  echo "Architectures: $ARCH"
  echo "Components: $COMP"
  echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
  echo "Description: Unofficial PowerShell packages for Termux (glibc)"
  echo "SHA256:"
  for f in "$bindir"/Packages*; do
    p=${f#"$REPO/dists/$SUITE/"}
    echo " $(sha256sum "$f" | cut -d' ' -f1) $(stat -c %s "$f") $p"
  done
} > "$rel"

if [ -n "${SIGN_KEY:-}" ]; then
  gpgargs=(--batch --yes --pinentry-mode loopback --local-user "$SIGN_KEY")
  [ -n "${GPG_PASSPHRASE_FILE:-}" ] && gpgargs+=(--passphrase-file "$GPG_PASSPHRASE_FILE")
  gpg "${gpgargs[@]}" --clearsign -o "$REPO/dists/$SUITE/InRelease" "$rel"
  gpg "${gpgargs[@]}" -abs -o "$REPO/dists/$SUITE/Release.gpg" "$rel"
  # What apt will do with the published key: verify both signatures with gpgv
  # against the keyring file alone.
  gpgv --keyring "$(realpath "$KEYRING_FILE")" "$REPO/dists/$SUITE/InRelease" 2>/dev/null \
    || die "InRelease does not verify against $KEYRING_FILE"
  gpgv --keyring "$(realpath "$KEYRING_FILE")" "$REPO/dists/$SUITE/Release.gpg" "$rel" 2>/dev/null \
    || die "Release.gpg does not verify against $KEYRING_FILE"
  log "signed with $sign_fpr and verified against $KEYRING_FILE"
else
  log "WARNING: SIGN_KEY not set, repository is UNSIGNED"
fi

touch "$REPO/.nojekyll"
log "repository written to $REPO"
