#!/usr/bin/env bash
# Build a Termux (glibc) .deb from an official PowerShell linux-arm64 release.
#
# Usage: build-deb.sh <pwsh|pwsh-preview> <tag> <outdir>
# Prints the path of the built .deb on stdout (everything else goes to stderr).
#
# Env: PATCHELF          patchelf binary (default: patchelf)
#      TERMUX_PREFIX     (default: /data/data/com.termux/files/usr)
#      REVISION          packaging revision (default: 1)
#      DEB_COMPRESSION   xz | gzip (default: xz)
set -euo pipefail
umask 022   # deterministic package permissions regardless of the caller's umask

PKG=${1:?package name: pwsh | pwsh-preview}
TAG=${2:?release tag, e.g. v7.7.0}
OUT=${3:?output directory}
TERMUX_PREFIX=${TERMUX_PREFIX:-/data/data/com.termux/files/usr}
PATCHELF=${PATCHELF:-patchelf}
REVISION=${REVISION:-1}
DEB_COMPRESSION=${DEB_COMPRESSION:-xz}

log() { printf '[build-deb] %s\n' "$*" >&2; }
die() { printf '[build-deb] ERROR: %s\n' "$*" >&2; exit 1; }

case "$PKG" in pwsh | pwsh-preview) ;; *) die "package must be pwsh or pwsh-preview" ;; esac
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || die "unexpected tag format: $TAG"
command -v "$PATCHELF" >/dev/null || die "patchelf not found (set PATCHELF=...)"

ver=${TAG#v}
# Debian version: 7.7.0-rc.1 -> 7.7.0~rc.1 so prereleases sort before the final release
deb_ver="${ver/-/'~'}-${REVISION}"
asset="powershell-${ver}-linux-arm64.tar.gz"
base="https://github.com/PowerShell/PowerShell/releases/download/${TAG}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

log "downloading $asset"
curl -fsSL --retry 3 -o "$work/$asset" "$base/$asset"
curl -fsSL --retry 3 -o "$work/hashes.sha256" "$base/hashes.sha256"

# Microsoft publishes hashes.sha256 as UTF-16 with a BOM, so decode it properly.
expected=$(python3 - "$work/hashes.sha256" "$asset" <<'PY'
import sys
text = open(sys.argv[1], "rb").read().decode("utf-16" if open(sys.argv[1], "rb").read(2) in (b"\xff\xfe", b"\xfe\xff") else "utf-8")
for line in text.splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1].lstrip("*") == sys.argv[2]:
        print(parts[0].lower())
        break
PY
)
[ -n "$expected" ] || die "no checksum for $asset in hashes.sha256"
actual=$(sha256sum "$work/$asset" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || die "checksum mismatch for $asset (expected $expected, got $actual)"
log "sha256 verified"

stage="$work/stage"
inst="$stage$TERMUX_PREFIX/opt/$PKG"
mkdir -p "$inst"
tar -xzf "$work/$asset" -C "$inst" --no-same-owner
chmod -R go-w,a+rX "$inst"
[ -f "$inst/pwsh" ] || die "pwsh binary missing from archive"

# Point every ELF executable at Termux's glibc loader. We do NOT use glibc-runner:
# it launches programs as `ld.so <prog>`, and the .NET host then looks for pwsh.dll
# next to ld.so instead of next to pwsh.
interp="$TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1"
rpath="$TERMUX_PREFIX/glibc/lib:$TERMUX_PREFIX/opt/$PKG"
patched=0
while IFS= read -r -d '' f; do
  if "$PATCHELF" --print-interpreter "$f" >/dev/null 2>&1; then
    "$PATCHELF" --set-interpreter "$interp" "$f"
    "$PATCHELF" --set-rpath "$rpath" "$f"
    patched=$((patched + 1))
  fi
done < <(find "$inst" -type f -print0)
[ "$patched" -ge 1 ] || die "no ELF executables were patched"
[ "$("$PATCHELF" --print-interpreter "$inst/pwsh")" = "$interp" ] || die "pwsh interpreter not patched"
log "patched $patched ELF executable(s)"

mkdir -p "$stage$TERMUX_PREFIX/bin" "$stage$TERMUX_PREFIX/share/doc/$PKG"
ln -s "../opt/$PKG/pwsh" "$stage$TERMUX_PREFIX/bin/$PKG"
{
  echo "Unofficial Termux repackaging of PowerShell $ver (https://github.com/PowerShell/PowerShell)."
  echo "Not affiliated with or endorsed by Microsoft. Upstream license follows."
  echo
  cat "$inst/LICENSE.txt"
} > "$stage$TERMUX_PREFIX/share/doc/$PKG/copyright"

installed_kb=$(du -sk "$stage" | cut -f1)
mkdir -p "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CTRL
Package: $PKG
Version: $deb_ver
Architecture: aarch64
Maintainer: pwsh-termux packagers <noreply@users.noreply.github.com>
Installed-Size: $installed_kb
Depends: glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc
Section: shells
Priority: optional
Homepage: https://github.com/PowerShell/PowerShell
Description: PowerShell $ver for Termux (unofficial repackaging)
 Unofficial repackaging of Microsoft's official linux-arm64 PowerShell
 release for Termux (glibc). Not affiliated with or endorsed by Microsoft.
 The binary is verified against Microsoft's published SHA-256 hash and
 patched to run on Termux's glibc loader.
CTRL

mkdir -p "$OUT"
deb="$OUT/${PKG}_${deb_ver}_aarch64.deb"
dpkg-deb --root-owner-group -Z"$DEB_COMPRESSION" --build "$stage" "$deb" >&2
log "built $deb"

# A record of the build for the SBOMs (make-sboms.sh); not part of the package.
python3 - "${deb%.deb}.build.json" "$PKG" "$deb_ver" "$TAG" "$base/$asset" "$actual" \
  "$("$PATCHELF" --version | awk '{print $2}')" <<'PY'
import json, sys
out, pkg, ver, tag, url, sha, patchelf = sys.argv[1:8]
json.dump({"package": pkg, "version": ver, "upstream_tag": tag,
           "upstream_url": url, "upstream_sha256": sha,
           "patchelf_version": patchelf}, open(out, "w"), indent=2)
PY
printf '%s\n' "$deb"
