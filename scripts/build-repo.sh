#!/usr/bin/env bash
# Assemble a signed apt repository from .deb files.
#
# Usage: build-repo.sh <debs-dir> <repo-dir>
# Env:   SIGN_KEY   gpg key id/fingerprint to sign with. If unset the repo is
#                   left UNSIGNED (fine for local tests, not for publishing).
#        GPG_PASSPHRASE_FILE  optional passphrase file for the signing key
#
# Layout (suite "stable", component "main", arch "aarch64"):
#   repo/pool/main/<pkg>/*.deb
#   repo/dists/stable/{Release,InRelease,Release.gpg}
#   repo/dists/stable/main/binary-aarch64/Packages{,.gz,.xz}
#   repo/pwsh-termux.gpg  pwsh-termux.asc   (public key)
# The website is merged in afterwards by assemble-site.sh.
set -euo pipefail

DEBS=${1:?debs directory}
REPO=${2:?repo output directory}
SUITE=stable COMP=main ARCH=aarch64

log() { printf '[build-repo] %s\n' "$*" >&2; }

shopt -s nullglob
debs=("$DEBS"/*.deb)
[ "${#debs[@]}" -gt 0 ] || { echo "no .deb files in $DEBS" >&2; exit 1; }

rm -rf "$REPO"
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
  gpg --batch --export "$SIGN_KEY" > "$REPO/pwsh-termux.gpg"
  gpg --batch --armor --export "$SIGN_KEY" > "$REPO/pwsh-termux.asc"
  log "signed with $SIGN_KEY"
else
  log "WARNING: SIGN_KEY not set, repository is UNSIGNED"
fi

touch "$REPO/.nojekyll"
log "repository written to $REPO"
