#!/usr/bin/env bash
# Tests of build-deb.sh, offline: a stub `curl` serves fake PowerShell
# releases (a tarball with real ELF executables, copied from this machine,
# and Microsoft's hashes.sha256, UTF-16 with a BOM or UTF-8) from a folder,
# and the real patchelf and dpkg-deb build the package. Checks the package
# (name, version, control fields, the patched loader and rpath, the command
# link, the copyright, the timestamps), the build record make-sboms.sh reads,
# that a second build gives the same bytes, and every refusal: a bad package
# name or tag, no patchelf, a failed download, no checksum, a wrong checksum,
# no pwsh, nothing to patch, pwsh not patched, a bad SOURCE_DATE_EPOCH. Runs
# on Termux and on CI; touches nothing outside a temporary folder.
#
# Usage: test-build-deb.sh
# Env:   PATCHELF  the patchelf binary (default: patchelf; on Termux,
#                  $PREFIX/glibc/bin/patchelf)
set -euo pipefail
umask 022
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
BUILD_DEB=$SCRIPTS_DIR/build-deb.sh
export PATCHELF=${PATCHELF:-patchelf}
command -v "$PATCHELF" >/dev/null || { echo "test-build-deb.sh needs patchelf (set PATCHELF=...)" >&2; exit 1; }
unset TERMUX_PREFIX REVISION DEB_COMPRESSION SOURCE_DATE_EPOCH
LOADER=$DEFAULT_TERMUX_PREFIX/glibc/lib/ld-linux-aarch64.so.1
RELEASES_URL=https://github.com/PowerShell/PowerShell/releases/download

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh;
# stdout goes to out.log, stderr to err.log.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>"$T/err.log"; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -E 'ERROR|curl' "$T/err.log" | tail -1)"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log" "$T/err.log"
  fi
}
# refuse <reason> <description> <command...>: the command fails, for that
# reason (a fixed string in what it printed).
refuse() {
  local reason=$1; shift
  expect refuse "$@"
  if ! grep -qF -- "$reason" "$T/err.log"; then fail "  not for the expected reason: $reason"; fi
}
# check <description> <command...>: the command succeeds.
check() {
  local what=$1; shift
  if "$@"; then pass "  $what"; else fail "  $what"; fi
}
# same <description> <got> <expected>
same() { if [ "$2" = "$3" ]; then pass "  $1"; else fail "  $1: got [$2], expected [$3]"; fi; }

# The stub curl: `curl ... -o <file> <url>` copies the file under
# $STUB_DIR/upstream that the release URL names, or fails as curl -f does.
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<STUB
#!/bin/sh
out= url=
while [ "\$#" -gt 0 ]; do
  case \$1 in
    -o) out=\$2; shift ;;
    http*) url=\$1 ;;
  esac
  shift
done
printf '%s\n' "\$url" >> "\$STUB_DIR/urls.log"
src=\$STUB_DIR/upstream/\${url#$RELEASES_URL/}
[ -f "\$src" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cp "\$src" "\$out"
STUB
chmod 755 "$T/bin/curl"
export STUB_DIR=$T PATH="$T/bin:$PATH"

# A real ELF executable with a loader, for patchelf to patch.
ELF=$T/elf
cp -L "$(command -v sleep)" "$ELF"
chmod 755 "$ELF"

# content <name> <file...>: a release's files in $T/content/<name>; each file
# is "elf" (an ELF executable named pwsh), "script" (pwsh as a shell script),
# "helper" (a second ELF executable), "dll" or "license".
content() {
  local d=$T/content/$1 f; shift
  mkdir -p "$d"
  for f in "$@"; do
    case $f in
      elf) cp "$ELF" "$d/pwsh" ;;
      script) printf '#!/bin/sh\necho pwsh\n' > "$d/pwsh"; chmod 755 "$d/pwsh" ;;
      helper) cp "$ELF" "$d/createdump" ;;
      dll) printf 'not an ELF file\n' > "$d/pwsh.dll" ;;
      license) printf 'MIT License\n\nCopyright (c) Microsoft Corporation.\n' > "$d/LICENSE.txt" ;;
    esac
  done
  # Microsoft's tarball keeps file times; the newest becomes SOURCE_DATE_EPOCH.
  find "$d" -exec touch -d @1700000000 {} +
  if [ -e "$d/pwsh" ]; then touch -d @1700000100 "$d/pwsh"; fi
}

# upstream <tag> <content-name> <utf16|utf8|other|wrong>: publish the release
# for the stub curl, with its hashes.sha256 in that form ("other" lists
# another asset only, "wrong" the asset with another hash).
upstream() {
  local tag=$1 name=$2 form=$3 d=$T/upstream/$1 asset hash
  asset=powershell-${tag#v}-linux-arm64.tar.gz
  mkdir -p "$d"
  tar -C "$T/content/$name" -czf "$d/$asset" .
  hash=$(sha256_of "$d/$asset")
  case $form in
    other) asset=powershell-${tag#v}-linux-x64.tar.gz ;;
    wrong) hash=$(printf 'other' | sha256sum | cut -d' ' -f1) ;;
  esac
  # Microsoft writes "<HASH> *<asset>", upper-case, CRLF, UTF-16 with a BOM.
  python3 - "$d/hashes.sha256" "$hash" "$asset" "$form" <<'PY'
import sys
out, sha, asset, form = sys.argv[1:5]
text = f"{sha.upper()} *powershell-other.zip\r\n{sha.upper()} *{asset}\r\n"
data = text.encode("utf-8") if form == "utf8" else b"\xff\xfe" + text.encode("utf-16-le")
open(out, "wb").write(data)
PY
}

build() { bash "$BUILD_DEB" "$@"; }

content good elf helper dll license
upstream v7.5.1 good utf16

echo "== a stable release (hashes.sha256 in UTF-16)"
expect accept "pwsh v7.5.1" build pwsh v7.5.1 "$T/out1"
DEB=$T/out1/pwsh_7.5.1-1_aarch64.deb
same "prints the package's path" "$(cat "$T/out.log")" "$DEB"
same "downloads the tarball and the hashes" "$(cat "$T/urls.log")" \
  "$(printf '%s\n' "$RELEASES_URL/v7.5.1/powershell-7.5.1-linux-arm64.tar.gz" "$RELEASES_URL/v7.5.1/hashes.sha256")"
same "Package, Version, Architecture" "$(dpkg-deb -f "$DEB" Package Version Architecture)" \
  "$(printf 'Package: pwsh\nVersion: 7.5.1-1\nArchitecture: aarch64')"
check "Depends on Termux's glibc packages" grep -qx 'Depends: glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc' \
  <(dpkg-deb -f "$DEB")
check "Installed-Size is a number" grep -qE '^Installed-Size: [0-9]+$' <(dpkg-deb -f "$DEB")
X=$T/x1
dpkg-deb -x "$DEB" "$X"
INST=$X$DEFAULT_TERMUX_PREFIX/opt/pwsh
same "pwsh runs with Termux's glibc loader" "$("$PATCHELF" --print-interpreter "$INST/pwsh")" "$LOADER"
same "and finds its libraries" "$("$PATCHELF" --print-rpath "$INST/pwsh")" \
  "$DEFAULT_TERMUX_PREFIX/glibc/lib:$DEFAULT_TERMUX_PREFIX/opt/pwsh"
same "every ELF executable is patched" "$("$PATCHELF" --print-interpreter "$INST/createdump")" "$LOADER"
check "other files are left as they are" cmp -s "$INST/pwsh.dll" "$T/content/good/pwsh.dll"
same "the pwsh command" "$(readlink "$X$DEFAULT_TERMUX_PREFIX/bin/pwsh")" ../opt/pwsh/pwsh
check "the copyright names the release and has Microsoft's license" \
  grep -qxF 'Copyright (c) Microsoft Corporation.' "$X$DEFAULT_TERMUX_PREFIX/share/doc/pwsh/copyright"
check "  ... after the repackaging notice" \
  grep -qF 'Unofficial Termux repackaging of PowerShell 7.5.1' "$X$DEFAULT_TERMUX_PREFIX/share/doc/pwsh/copyright"
same "every file has the tarball's newest time" "$(stat -c %Y "$INST/pwsh.dll")" 1700000100
check "no file is writable by group or others" test -z "$(find "$X" -perm /022 ! -type l)"
RECORD=$T/out1/pwsh_7.5.1-1_aarch64.build.json
same "the build record" \
  "$(jq -r '[.package, .version, .upstream_tag, .upstream_url, .upstream_sha256] | join(" ")' "$RECORD")" \
  "pwsh 7.5.1-1 v7.5.1 $RELEASES_URL/v7.5.1/powershell-7.5.1-linux-arm64.tar.gz $(sha256_of "$T/upstream/v7.5.1/powershell-7.5.1-linux-arm64.tar.gz")"
same "  with patchelf's version" "$(jq -r .patchelf_version "$RECORD")" "$("$PATCHELF" --version | awk '{print $2}')"

expect accept "the same release again" build pwsh v7.5.1 "$T/out2"
check "gives the same bytes (reproducible)" cmp -s "$DEB" "$T/out2/pwsh_7.5.1-1_aarch64.deb"

echo "== a prerelease (hashes.sha256 in UTF-8), with every option"
content preview elf license
upstream v7.6.0-preview.4 preview utf8
expect accept "pwsh-preview v7.6.0-preview.4" \
  env REVISION=2 DEB_COMPRESSION=gzip SOURCE_DATE_EPOCH=1600000000 bash "$BUILD_DEB" pwsh-preview v7.6.0-preview.4 "$T/out3"
DEB=$T/out3/pwsh-preview_7.6.0~preview.4-2_aarch64.deb
same "~ in the version, so it sorts before 7.6.0" "$(cat "$T/out.log")" "$DEB"
check "gzip compression" grep -qa 'data.tar.gz' "$DEB"
X=$T/x3
dpkg-deb -x "$DEB" "$X"
same "the pwsh-preview command" "$(readlink "$X$DEFAULT_TERMUX_PREFIX/bin/pwsh-preview")" ../opt/pwsh-preview/pwsh
same "its own install folder in the rpath" "$("$PATCHELF" --print-rpath "$X$DEFAULT_TERMUX_PREFIX/opt/pwsh-preview/pwsh")" \
  "$DEFAULT_TERMUX_PREFIX/glibc/lib:$DEFAULT_TERMUX_PREFIX/opt/pwsh-preview"
same "SOURCE_DATE_EPOCH as given" "$(stat -c %Y "$X$DEFAULT_TERMUX_PREFIX/opt/pwsh-preview/LICENSE.txt")" 1600000000

echo "== refusals"
refuse 'package must be' "a package other than pwsh and pwsh-preview" build pwsh-lts v7.5.1 "$T/r"
refuse 'unexpected tag format' "a tag without the v" build pwsh 7.5.1 "$T/r"
refuse 'unexpected tag format' "a tag with a path in it" build pwsh v7.5.1/../x "$T/r"
refuse 'patchelf not found' "no patchelf" env PATCHELF="$T/no-patchelf" bash "$BUILD_DEB" pwsh v7.5.1 "$T/r"
refuse 'error: 404' "a release that is not there (download fails)" build pwsh v7.9.9 "$T/r"
upstream v7.5.2 good other
refuse 'no checksum for' "hashes.sha256 without the tarball" build pwsh v7.5.2 "$T/r"
upstream v7.5.3 good wrong
refuse 'checksum mismatch' "a tarball that does not match its hash" build pwsh v7.5.3 "$T/r"
content no-pwsh helper license
upstream v7.5.4 no-pwsh utf16
refuse 'pwsh binary missing' "a tarball without pwsh" build pwsh v7.5.4 "$T/r"
content no-elf script license
upstream v7.5.5 no-elf utf16
refuse 'no ELF executables were patched' "a tarball without an ELF executable" build pwsh v7.5.5 "$T/r"
content script-pwsh script helper license
upstream v7.5.6 script-pwsh utf16
refuse 'pwsh interpreter not patched' "a pwsh that is not an ELF executable" build pwsh v7.5.6 "$T/r"
refuse 'no usable SOURCE_DATE_EPOCH' "a SOURCE_DATE_EPOCH that is not a number" \
  env SOURCE_DATE_EPOCH=yesterday bash "$BUILD_DEB" pwsh v7.5.1 "$T/r"
check "no package after a refusal" test ! -e "$T/r"

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
