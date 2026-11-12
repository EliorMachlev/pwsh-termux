#!/usr/bin/env bash
# Build the pwsh-termux-keyring .deb: the repository's public keys and the apt
# source that trusts them for this repository only (signed-by), so a user sets
# the repository up by installing one package and removes it with one
# `pkg remove`. The keys come from keys/pwsh-termux-archive-keyring.gpg, which
# is committed to Git; the build is reproducible (same commit, same bytes).
#
# A planned key rotation reaches users through `pkg upgrade`: the new key is
# added to keys/ while the old key still signs, so this package delivers it
# before the switch. A compromised key cannot be replaced that way; users
# reinstall this package by hand. See docs/markDown/engineering/release.md.
#
# Usage: build-keyring.sh <outdir>
# Prints the path of the built .deb on stdout (everything else goes to stderr)
# and writes <deb>.build.json next to it for make-sboms.sh.
#
# Env: KEYRING_FILE      TEST ONLY: a different public keyring (for a throwaway
#                        key in local and CI tests). Default and production:
#                        keys/pwsh-termux-archive-keyring.gpg.
#      SOURCE_DATE_EPOCH timestamp for every file in the package. Default: the
#                        commit time of the keyring file in Git; if it has
#                        none (not a checkout, or an uncommitted test file),
#                        the creation time of its newest key.
#      TERMUX_PREFIX     (default: /data/data/com.termux/files/usr)
set -euo pipefail
umask 022   # deterministic package permissions regardless of the caller's umask

# Bump on every change to the package's content: a key added or removed, the
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
  SOURCE_DATE_EPOCH=$(git -C "$ROOT" log -1 --format=%ct -- "$KEYRING_FILE" 2>/dev/null || true)
  if [ -z "$SOURCE_DATE_EPOCH" ]; then
    SOURCE_DATE_EPOCH=$(gpg --batch --show-keys --with-colons "$KEYRING_FILE" 2>/dev/null \
      | awk -F: '$1 == "pub" && $6 > max {max = $6} END {print max}')
  fi
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
 Installs the public keys that sign the pwsh-termux apt repository and a
 source line that trusts them for this repository only (signed-by).
 A planned key rotation arrives with pkg upgrade; a compromised key needs
 this package reinstalled by hand. Removing it removes both files.
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
