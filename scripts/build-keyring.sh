#!/usr/bin/env bash
# Build the pwsh-termux-keyring .deb: the repository's public keys and the
# apt source that trusts them for this repository only (signed-by), so a user
# sets the repository up by installing one package and removes it with one
# `pkg remove`. The keys come from keys/pwsh-termux-archive-keyring.gpg, which
# is committed to Git: the online signing key, the offline recovery key once
# keys/RECOVERY names it, and the next online key while keys/ROTATION names it
# (check-keys.sh). The build is deterministic (same key file and script, same
# bytes).
#
# New keys reach users through `pkg upgrade`: a planned rotation ships the
# next key while the current one still signs; after a lost or compromised
# online key, the maintainer signs the index that carries the new keyring with
# the recovery key. Only a user who misses those windows, or a compromise with
# no recovery key, needs a manual reinstall. See
# docs/markDown/engineering/release.md.
#
# Usage: build-keyring.sh <outdir>
# Prints the path of the built .deb on stdout (everything else goes to stderr)
# and writes <deb>.build.json next to it for make-sboms.sh.
#
# Env: KEYRING_FILE      TEST ONLY: a different public keyring (for a throwaway
#                        key in local and CI tests). Default and production:
#                        keys/pwsh-termux-archive-keyring.gpg.
#      SOURCE_DATE_EPOCH timestamp for every file in the package. Default: the
#                        creation time of the key, read from the key file, so
#                        the bytes depend on the file's content only (not on
#                        Git history or the time of the build).
#      TERMUX_PREFIX     (default: /data/data/com.termux/files/usr)
set -euo pipefail
umask 022   # deterministic package permissions regardless of the caller's umask

# Bump on every change to the package's content: a key added or dropped, the
# source line, this script's layout or control fields.
KEYRING_VERSION=1.0.0

OUT=${1:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
KEYRING_FILE=${KEYRING_FILE:-$ROOT/keys/pwsh-termux-archive-keyring.gpg}
if [ "$KEYRING_FILE" -ef "$ROOT/keys/pwsh-termux-archive-keyring.gpg" ]; then
  source_name=keys/pwsh-termux-archive-keyring.gpg
else
  source_name="$KEYRING_FILE (test keyring)"
fi
TERMUX_PREFIX=${TERMUX_PREFIX:-/data/data/com.termux/files/usr}
PKG=pwsh-termux-keyring
KEYRING_PATH=$TERMUX_PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg
SOURCE_LINE="deb [signed-by=$KEYRING_PATH] https://pwsh-termux.machlev.org stable main"

log() { printf '[build-keyring] %s\n' "$*" >&2; }
die() { printf '[build-keyring] ERROR: %s\n' "$*" >&2; exit 1; }

bash "$HERE/check-keys.sh" "$KEYRING_FILE" >&2 || die "$KEYRING_FILE failed the key check"

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(gpg --batch --show-keys --with-colons "$KEYRING_FILE" 2>/dev/null \
    | awk -F: '$1 == "pub" {print $6; exit}')
fi
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || die "no usable SOURCE_DATE_EPOCH: '$SOURCE_DATE_EPOCH'"
export SOURCE_DATE_EPOCH
log "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
stage="$work/stage"

mkdir -p "$stage$TERMUX_PREFIX/share/keyrings" \
         "$stage$TERMUX_PREFIX/etc/apt/sources.list.d" \
         "$stage$TERMUX_PREFIX/share/doc/$PKG"
install -m 644 "$KEYRING_FILE" "$stage$KEYRING_PATH"
# Same file name as the manual install: two sources for one URI with
# different Signed-By values are an apt error.
printf '%s\n' "$SOURCE_LINE" > "$stage$TERMUX_PREFIX/etc/apt/sources.list.d/pwsh-termux.list"
{
  echo "Public keys and apt source of the unofficial pwsh-termux repository"
  echo "(https://pwsh-termux.machlev.org). MIT license: see the project's LICENSE at"
  echo "https://github.com/EliorMachlev/pwsh-termux."
} > "$stage$TERMUX_PREFIX/share/doc/$PKG/copyright"

# Installed-Size as dpkg-gencontrol counts it (KiB per file, rounded up; one
# per directory), so it does not depend on the build machine's file system.
installed_kb=$(find "$stage" -mindepth 1 -printf '%y %s\n' \
  | awk '$1 == "f" {kb += int(($2 + 1023) / 1024); next} {kb += 1} END {print kb}')

mkdir -p "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CTRL
Package: $PKG
Version: $KEYRING_VERSION
Architecture: all
Maintainer: pwsh-termux packagers <noreply@users.noreply.github.com>
Installed-Size: $installed_kb
Section: misc
Priority: optional
Homepage: https://pwsh-termux.machlev.org/
Description: Signing keys and apt source for the pwsh-termux repository
 Installs the public keys of the pwsh-termux apt repository and a source
 line that trusts them for this repository only (signed-by).
 New keys arrive with pkg upgrade (planned rotation, and recovery with
 the offline key once it is set up). Removing it removes both files.
CTRL

# Every timestamp is SOURCE_DATE_EPOCH, and xz runs single-threaded (its
# multi-threaded output depends on the number of CPUs).
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

mkdir -p "$OUT"
deb="$OUT/${PKG}_${KEYRING_VERSION}_all.deb"
dpkg-deb --root-owner-group --threads-max=1 -Zxz -z9 --build "$stage" "$deb" >&2
log "built $deb"

# A record of the build for the SBOMs (make-sboms.sh); not part of the package.
python3 - "${deb%.deb}.build.json" "$PKG" "$KEYRING_VERSION" \
  "$source_name" "$(sha256sum "$KEYRING_FILE" | cut -d' ' -f1)" "$SOURCE_DATE_EPOCH" <<'PY'
import json, sys
out, pkg, ver, src, sha, epoch = sys.argv[1:7]
json.dump({"package": pkg, "version": ver, "architecture": "all",
           "source_file": src,
           "source_sha256": sha, "source_date_epoch": int(epoch)},
          open(out, "w"), indent=2)
PY
printf '%s\n' "$deb"
