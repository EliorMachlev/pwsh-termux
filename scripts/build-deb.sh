#!/usr/bin/env bash
# Build a Termux (glibc) .deb from an official PowerShell Linux ARM release
# (linux-arm64 for aarch64, linux-arm32 for arm).
#
# Usage: build-deb.sh <pwsh|pwsh-preview> <tag> <outdir>
# Prints the path of the built .deb on stdout (everything else goes to stderr).
#
# Env: PATCHELF          patchelf binary (default: patchelf)
#      PWSH_ARCH         aarch64 | arm: the Termux architecture to build for
#                        (default: aarch64)
#      TERMUX_PREFIX     (default: /data/data/com.termux/files/usr)
#      DEB_COMPRESSION   xz | gzip (default: xz)
#      SOURCE_DATE_EPOCH timestamp for every file in the package. Default: the
#                        newest file time in Microsoft's (verified) tarball.
#      PACKAGING_REVISIONS  TEST ONLY: the revisions file to read instead of
#                        packaging-revisions at the repository's root
#
# The Debian revision is not an option: it comes from packaging-revisions,
# committed, so every run builds the same version; 1 when the release has no
# line there.
#
# The build is reproducible: the same release, script and tools give the same
# bytes, so the daily run rebuilds an unchanged release byte for byte and the
# repository index does not change (see build-repo.sh, Valid-Until).
set -euo pipefail
umask 022   # deterministic package permissions regardless of the caller's umask
source "$(dirname "$0")/lib/common.sh"

PKG=${1:?package name: pwsh | pwsh-preview}
TAG=${2:?release tag, e.g. v7.7.0}
OUT_DIR=${3:?output directory}
TERMUX_PREFIX=${TERMUX_PREFIX:-$DEFAULT_TERMUX_PREFIX}
PATCHELF=${PATCHELF:-patchelf}
PWSH_ARCH=${PWSH_ARCH:-$APT_ARCH}
DEB_COMPRESSION=${DEB_COMPRESSION:-xz}
REVISIONS_FILE=${PACKAGING_REVISIONS:-$REPO_ROOT/packaging-revisions}

readonly VERSION_PATTERN='[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?'
readonly TAG_REGEX="^v${VERSION_PATTERN}\$"
readonly UPSTREAM_VERSION_REGEX="^${VERSION_PATTERN}\$"
readonly REVISION_REGEX='^[1-9][0-9]*$'
readonly UPSTREAM_RELEASES_URL=https://github.com/PowerShell/PowerShell/releases/download
readonly CHECKSUMS_ASSET=hashes.sha256
readonly MAINTAINER="pwsh-termux packagers <noreply@users.noreply.github.com>"
readonly DEPENDS="glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc"
readonly GLIBC_LIB_DIR=$TERMUX_PREFIX/glibc/lib
# Per architecture: Microsoft's tarball suffix and Termux's glibc loader name.
case "$PWSH_ARCH" in
  aarch64) readonly UPSTREAM_ARCH=arm64 LOADER=ld-linux-aarch64.so.1 ;;
  arm) readonly UPSTREAM_ARCH=arm32 LOADER=ld-linux-armhf.so.3 ;;
  *) die "PWSH_ARCH must be aarch64 or arm, not $PWSH_ARCH" ;;
esac
readonly ELF_INTERPRETER=$GLIBC_LIB_DIR/$LOADER
readonly INSTALL_DIR=$TERMUX_PREFIX/opt/$PKG
readonly ELF_RPATH=$GLIBC_LIB_DIR:$INSTALL_DIR

# Removed on exit.
WORK_DIR=
# Set by verify_download.
ASSET_SHA256=

check_arguments() {
  case "$PKG" in pwsh | pwsh-preview) ;; *) die "package must be pwsh or pwsh-preview" ;; esac
  [[ "$TAG" =~ $TAG_REGEX ]] || die "unexpected tag format: $TAG"
  command -v "$PATCHELF" >/dev/null || die "patchelf not found (set PATCHELF=...)"
}

# packaging_revision <version>: the revision packaging-revisions gives this
# package at that upstream version (7.7.0, 7.8.0-preview.1), or 1 if the file
# or the line is absent. Every line is checked, not only the one wanted: a
# malformed line, or a second line for the same package and version, stops
# the build rather than quietly building revision 1.
packaging_revision() {
  local ver=$1 revision=1 n=0 line pkg upstream rev extra where
  local -A seen=()
  if [ ! -e "$REVISIONS_FILE" ]; then
    printf '1\n'
    return 0
  fi
  [ -f "$REVISIONS_FILE" ] || die "$REVISIONS_FILE is not a regular file"
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r pkg upstream rev extra <<<"$line"
    where="$REVISIONS_FILE line $n"
    if [ -z "$rev" ] || [ -n "$extra" ]; then die "$where: want <package> <upstream version> <revision>"; fi
    case "$pkg" in pwsh | pwsh-preview) ;; *) die "$where: package must be pwsh or pwsh-preview" ;; esac
    [[ "$upstream" =~ $UPSTREAM_VERSION_REGEX ]] || die "$where: not an upstream version (7.7.0, 7.8.0-preview.1)"
    [[ "$rev" =~ $REVISION_REGEX ]] || die "$where: the revision must be a positive integer without a leading 0"
    [ -z "${seen["$pkg $upstream"]:-}" ] || die "$where: a second line for $pkg $upstream"
    seen["$pkg $upstream"]=1
    if [ "$pkg" = "$PKG" ] && [ "$upstream" = "$ver" ]; then revision=$rev; fi
  done < "$REVISIONS_FILE" || die "cannot read $REVISIONS_FILE"
  printf '%s\n' "$revision"
}

# expected_sha256 <hashes-file> <asset>: the asset's hash in Microsoft's
# hashes.sha256, which is UTF-16 with a BOM, so it is decoded properly.
expected_sha256() {
  python3 - "$1" "$2" <<'PY'
import sys
text = open(sys.argv[1], "rb").read().decode("utf-16" if open(sys.argv[1], "rb").read(2) in (b"\xff\xfe", b"\xfe\xff") else "utf-8")
for line in text.splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1].lstrip("*") == sys.argv[2]:
        print(parts[0].lower())
        break
PY
}

# verify_download <asset-file> <hashes-file>: the asset matches its hash in
# hashes-file; sets ASSET_SHA256.
verify_download() {
  local asset_file=$1 hashes_file=$2 asset expected actual
  asset=$(basename "$asset_file")
  expected=$(expected_sha256 "$hashes_file" "$asset")
  [ -n "$expected" ] || die "no checksum for $asset in $CHECKSUMS_ASSET"
  actual=$(sha256_of "$asset_file")
  [ "$expected" = "$actual" ] || die "checksum mismatch for $asset (expected $expected, got $actual)"
  log "sha256 verified"
  ASSET_SHA256=$actual
}

# unpack <tarball> <install-dir>
unpack() {
  local tarball=$1 inst=$2
  mkdir -p "$inst"
  tar -xzf "$tarball" -C "$inst" --no-same-owner
  chmod -R go-w,a+rX "$inst"
  [ -f "$inst/pwsh" ] || die "pwsh binary missing from archive"
}

# patch_elf_files <install-dir>: point every ELF executable at Termux's glibc
# loader. We do NOT use glibc-runner: it launches programs as `ld.so <prog>`,
# and the .NET host then looks for pwsh.dll next to ld.so instead of next to
# pwsh.
patch_elf_files() {
  local inst=$1 patched=0 f
  while IFS= read -r -d '' f; do
    if "$PATCHELF" --print-interpreter "$f" >/dev/null 2>&1; then
      "$PATCHELF" --set-interpreter "$ELF_INTERPRETER" "$f"
      "$PATCHELF" --set-rpath "$ELF_RPATH" "$f"
      patched=$((patched + 1))
    fi
  done < <(find "$inst" -type f -print0)
  [ "$patched" -ge 1 ] || die "no ELF executables were patched"
  [ "$("$PATCHELF" --print-interpreter "$inst/pwsh")" = "$ELF_INTERPRETER" ] || die "pwsh interpreter not patched"
  log "patched $patched ELF executable(s)"
}

# add_command_and_copyright <stage-dir> <install-dir> <version>
add_command_and_copyright() {
  local stage=$1 inst=$2 ver=$3
  mkdir -p "$stage$TERMUX_PREFIX/bin" "$stage$TERMUX_PREFIX/share/doc/$PKG"
  ln -s "../opt/$PKG/pwsh" "$stage$TERMUX_PREFIX/bin/$PKG"
  {
    echo "Unofficial Termux repackaging of PowerShell $ver (https://github.com/PowerShell/PowerShell)."
    echo "Not affiliated with or endorsed by Microsoft. Upstream license follows."
    echo
    cat "$inst/LICENSE.txt"
  } > "$stage$TERMUX_PREFIX/share/doc/$PKG/copyright"
}

# set_source_date_epoch <install-dir>: as given, or the newest file time in
# the unpacked tarball (tar keeps the times), so the bytes depend on the
# release only, not on the time of the build.
set_source_date_epoch() {
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH=$(find "$1" -type f -printf '%T@\n' | sort -n | tail -n1 | cut -d. -f1)
  fi
  [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || die "no usable SOURCE_DATE_EPOCH: '$SOURCE_DATE_EPOCH'"
  export SOURCE_DATE_EPOCH
  log "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
}

# write_control <stage-dir> <version> <deb-version>
write_control() {
  local stage=$1 ver=$2 deb_ver=$3 installed_kb
  installed_kb=$(installed_size_kib "$stage")
  mkdir -p "$stage/DEBIAN"
  cat > "$stage/DEBIAN/control" <<CTRL
Package: $PKG
Version: $deb_ver
Architecture: $PWSH_ARCH
Maintainer: $MAINTAINER
Installed-Size: $installed_kb
Depends: $DEPENDS
Section: shells
Priority: optional
Homepage: https://github.com/PowerShell/PowerShell
Description: PowerShell $ver for Termux (unofficial repackaging)
 Unofficial repackaging of Microsoft's official linux-$UPSTREAM_ARCH PowerShell
 release for Termux (glibc). Not affiliated with or endorsed by Microsoft.
 The binary is verified against Microsoft's published SHA-256 hash and
 patched to run on Termux's glibc loader.
CTRL
}

# write_build_record <deb> <deb-version> <asset-url> <asset-sha256>: for the
# SBOMs (make-sboms.sh); not part of the package.
write_build_record() {
  local deb=$1 deb_ver=$2 asset_url=$3 asset_sha=$4
  python3 - "${deb%.deb}.build.json" "$PKG" "$deb_ver" "$TAG" "$asset_url" "$asset_sha" \
    "$("$PATCHELF" --version | awk '{print $2}')" <<'PY'
import json, sys
out, pkg, ver, tag, url, sha, patchelf = sys.argv[1:8]
json.dump({"package": pkg, "version": ver, "upstream_tag": tag,
           "upstream_url": url, "upstream_sha256": sha,
           "patchelf_version": patchelf}, open(out, "w"), indent=2)
PY
}

main() {
  local ver revision deb_ver asset base_url stage deb
  check_arguments

  ver=${TAG#v}
  revision=$(packaging_revision "$ver")
  # Debian version: 7.7.0-rc.1 -> 7.7.0~rc.1 so prereleases sort before the final release
  deb_ver="${ver/-/'~'}-${revision}"
  log "version $deb_ver"
  asset="powershell-${ver}-linux-${UPSTREAM_ARCH}.tar.gz"
  base_url="$UPSTREAM_RELEASES_URL/${TAG}"

  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT

  log "downloading $asset"
  download_file "$base_url/$asset" "$WORK_DIR/$asset"
  download_file "$base_url/$CHECKSUMS_ASSET" "$WORK_DIR/$CHECKSUMS_ASSET"
  verify_download "$WORK_DIR/$asset" "$WORK_DIR/$CHECKSUMS_ASSET"

  stage="$WORK_DIR/stage"
  unpack "$WORK_DIR/$asset" "$stage$INSTALL_DIR"
  set_source_date_epoch "$stage$INSTALL_DIR"
  patch_elf_files "$stage$INSTALL_DIR"
  add_command_and_copyright "$stage" "$stage$INSTALL_DIR" "$ver"
  write_control "$stage" "$ver" "$deb_ver"

  deb="$OUT_DIR/${PKG}_${deb_ver}_${PWSH_ARCH}.deb"
  build_reproducible_deb "$stage" "$deb" -Z"$DEB_COMPRESSION"
  log "built $deb"

  write_build_record "$deb" "$deb_ver" "$base_url/$asset" "$ASSET_SHA256"
  printf '%s\n' "$deb"
}

main
