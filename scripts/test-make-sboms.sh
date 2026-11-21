#!/usr/bin/env bash
# Tests of make-sboms.sh, offline. The three tools it downloads (the SPDX
# validator, Syft and Microsoft's SBOM tool) are stubs that a stub `curl`
# serves, so the real pinned SHA-256 check refuses them: that refusal is the
# first test. The others let the downloads through (a stub `sha256sum -c`;
# every other sha256sum is the real one) and check the rest with stub tools
# that write minimal SBOMs and record their calls, and the real
# spdx-build-view.py: the four SBOMs of each package, each validated, the
# tools' arguments, the cleanup, and the refusals (no build record, no
# package, an SBOM the validator rejects, a failed Microsoft validation).
# Runs on Termux and on CI; touches nothing outside a temporary folder.
#
# Usage: test-make-sboms.sh
set -euo pipefail
umask 022
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
MAKE_SBOMS=$SCRIPTS_DIR/make-sboms.sh
unset KEYRING_FILE SOURCE_DATE_EPOCH

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
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -hE 'error|ERROR|FAILED|no ' "$T/err.log" "$T/out.log" | tail -1)"; fi
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
  if ! grep -qF -- "$reason" "$T/err.log" "$T/out.log"; then fail "  not for the expected reason: $reason"; fi
}
# check <description> <command...>: the command succeeds.
check() {
  local what=$1; shift
  if "$@"; then pass "  $what"; else fail "  $what"; fi
}
# same <description> <got> <expected>
same() { if [ "$2" = "$3" ]; then pass "  $1"; else fail "  $1: got [$2], expected [$3]"; fi; }

mkdir -p "$T/bin" "$T/payload/syft"
REAL_SHA256SUM=$(command -v sha256sum)

# The stub curl: `curl ... -o <file> <url>` writes the stub tool the URL names.
cat > "$T/bin/curl" <<'STUB'
#!/bin/sh
out= url=
while [ "$#" -gt 0 ]; do
  case $1 in
    -o) out=$2; shift ;;
    http*) url=$1 ;;
  esac
  shift
done
printf '%s\n' "$url" >> "$STUB_DIR/urls.log"
case $url in
  *tools-java-*-jar-with-dependencies.jar) cp "$STUB_DIR/payload/tools-java.jar" "$out" ;;
  *syft_*_linux_amd64.tar.gz) cp "$STUB_DIR/payload/syft.tar.gz" "$out" ;;
  *sbom-tool-linux-x64) cp "$STUB_DIR/payload/sbom-tool" "$out" ;;
  *) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
esac
STUB

# The stub sha256sum: with $STUB_DIR/trust-downloads, `sha256sum -c` accepts
# every file; anything else is the real sha256sum.
cat > "$T/bin/sha256sum" <<STUB
#!/bin/sh
if [ "\$1" = -c ] && [ -e "\$STUB_DIR/trust-downloads" ]; then
  while read -r _ file; do echo "\$file: OK"; done
  exit 0
fi
exec "$REAL_SHA256SUM" "\$@"
STUB

# The stub java: `java -jar <jar> Verify <file>` accepts JSON files, unless
# the file's name is in $STUB_DIR/invalid.
cat > "$T/bin/java" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/java.log"
[ "$1 $3" = "-jar Verify" ] || { echo "stub java: unexpected call: $*" >&2; exit 2; }
if grep -qxF "$(basename "$4")" "$STUB_DIR/invalid" 2>/dev/null || ! python3 -m json.tool "$4" >/dev/null 2>&1; then
  echo "The following errors were found: stub"; exit 0
fi
echo "This SPDX Document is valid."
STUB

# The stub syft (in its tarball): `syft dir:<root> -o <format>=<file> -q`
# writes the format and the files it saw.
cat > "$T/payload/syft/syft" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/syft.log"
root=${1#dir:} spec=${3%%=*} out=${3#*=}
python3 - "$root" "$spec" "$out" <<'PY'
import json, os, sys
root, spec, out = sys.argv[1:4]
files = sorted(os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs)
json.dump({"generator": "stub syft", "format": spec, "files": files}, open(out, "w"))
PY
STUB
chmod 755 "$T/payload/syft/syft"
tar -C "$T/payload/syft" -czf "$T/payload/syft.tar.gz" syft
printf 'not a real jar\n' > "$T/payload/tools-java.jar"

# The stub sbom-tool: `generate ... -pn <name> -pv <version> -m <drop>` writes
# the drop's manifest; `validate ... -o <file>` writes the result, a failure
# if $STUB_DIR/msft-fails exists.
cat > "$T/payload/sbom-tool" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/sbom-tool.log"
action=$1; shift
name= version= drop= out=
while [ "$#" -gt 0 ]; do
  case $1 in
    -pn) name=$2 ;;
    -pv) version=$2 ;;
    -m) drop=$2 ;;
    -o) out=$2 ;;
  esac
  shift
done
case $action in
  generate)
    mkdir -p "$drop/_manifest/spdx_3.0"
    printf '{"generator": "stub sbom-tool", "name": "%s", "version": "%s"}\n' "$name" "$version" \
      > "$drop/_manifest/spdx_3.0/manifest.spdx.json" ;;
  validate)
    if [ -e "$STUB_DIR/msft-fails" ]; then
      echo '{"Result": "Failure", "ValidationErrors": ["stub"]}' > "$out"
    else
      echo '{"Result": "Success"}' > "$out"
    fi ;;
esac
STUB
chmod 755 "$T/bin/curl" "$T/bin/sha256sum" "$T/bin/java"
export STUB_DIR=$T PATH="$T/bin:$PATH"

# The packages: the keyring package as build-keyring.sh builds it (with its
# record), and a small pwsh package with a record as build-deb.sh writes it.
DEBS=$T/debs
mkdir -p "$DEBS" "$T/pwsh/DEBIAN" "$T/pwsh/opt/pwsh"
bash "$SCRIPTS_DIR/build-keyring.sh" "$DEBS" >/dev/null 2>&1
printf 'pwsh\n' > "$T/pwsh/opt/pwsh/pwsh"
printf 'Package: pwsh\nVersion: 7.5.1-1\nArchitecture: aarch64\nMaintainer: t <t@example.invalid>\nDepends: glibc, zlib-glibc\nDescription: d\n d\n' \
  > "$T/pwsh/DEBIAN/control"
dpkg-deb --root-owner-group --build "$T/pwsh" "$DEBS/pwsh_7.5.1-1_aarch64.deb" >/dev/null
jq -n --arg sha "$(printf 'tarball' | sha256sum | cut -d' ' -f1)" \
  '{package: "pwsh", version: "7.5.1-1", upstream_tag: "v7.5.1",
    upstream_url: "https://github.com/PowerShell/PowerShell/releases/download/v7.5.1/powershell-7.5.1-linux-arm64.tar.gz",
    upstream_sha256: $sha, patchelf_version: "0.18.0"}' > "$DEBS/pwsh_7.5.1-1_aarch64.build.json"
KEYRING_DEB=("$DEBS"/"$KEYRING_PACKAGE"_*_all.deb)
KEYRING_BASE=$(basename "${KEYRING_DEB[0]%.deb}")

# sboms <debs-dir> <name>: make-sboms.sh into $T/<name>, with its own RUNNER_TEMP.
sboms() {
  mkdir -p "$T/$2-tmp"
  RUNNER_TEMP=$T/$2-tmp bash "$MAKE_SBOMS" "$1" "$T/$2"
}

echo "== the pinned hashes"
refuse 'did NOT match' "stub downloads do not match the pinned SHA-256" sboms "$DEBS" refused
same "the validator is checked before anything else is downloaded" "$(wc -l < "$T/urls.log")" 1
check "  the SPDX validator, version 2.0.7" grep -qF '/tools-java/2.0.7/tools-java-2.0.7-jar-with-dependencies.jar' "$T/urls.log"

echo "== the SBOMs of each package"
touch "$T/trust-downloads"
: > "$T/urls.log"
expect accept "two packages" sboms "$DEBS" out
SYFT_PINNED=$(grep -oP '^readonly SYFT_VERSION=\K\S+' "$SCRIPTS_DIR/make-sboms.sh")
check "  Syft $SYFT_PINNED and the SBOM tool downloaded" \
  grep -qF "/v$SYFT_PINNED/syft_${SYFT_PINNED}_linux_amd64.tar.gz" "$T/urls.log"
SBOM_TOOL_PINNED=$(grep -oP '^readonly MS_SBOM_TOOL_VERSION=\K\S+' "$SCRIPTS_DIR/make-sboms.sh")
check "  ... and the SBOM tool $SBOM_TOOL_PINNED" grep -qF "/v$SBOM_TOOL_PINNED/sbom-tool-linux-x64" "$T/urls.log"
for base in pwsh_7.5.1-1_aarch64 "$KEYRING_BASE"; do
  for kind in cdx.json build.spdx.json syft.spdx3.json msft.spdx3.json; do
    check "$base.$kind" test -s "$T/out/$base.$kind"
  done
done
same "CycloneDX 1.6 from Syft" "$(jq -r .format "$T/out/pwsh_7.5.1-1_aarch64.cdx.json")" "cyclonedx-json@1.6"
same "  over the package's files" "$(jq -r '.files | join(" ")' "$T/out/pwsh_7.5.1-1_aarch64.cdx.json")" "opt/pwsh/pwsh"
same "SPDX 3.0 from Syft" "$(jq -r .format "$T/out/pwsh_7.5.1-1_aarch64.syft.spdx3.json")" "spdx-json@3.0"
same "the packaging view is SPDX 2.3" "$(jq -r .spdxVersion "$T/out/pwsh_7.5.1-1_aarch64.build.spdx.json")" "SPDX-2.3"
same "Microsoft's SBOM names the package and version" \
  "$(jq -r '.name + " " + .version' "$T/out/pwsh_7.5.1-1_aarch64.msft.spdx3.json")" "pwsh 7.5.1-1"
check "  generated with the project's namespace and SPDX 3.0" \
  grep -qF -- '-pn pwsh -pv 7.5.1-1 -ps pwsh-termux' "$T/sbom-tool.log"
check "  ... and validated against the package's files" grep -qE '^validate -b .*/sbom-root-pwsh_7.5.1-1_aarch64 ' "$T/sbom-tool.log"
same "the SPDX validator checks the 2.3 and Syft files of each package" \
  "$(sed 's#.* Verify .*/##' "$T/java.log" | sort | tr '\n' ' ')" \
  "$KEYRING_BASE.build.spdx.json $KEYRING_BASE.syft.spdx3.json pwsh_7.5.1-1_aarch64.build.spdx.json pwsh_7.5.1-1_aarch64.syft.spdx3.json "
check "the unpacked packages are removed" test -z "$(find "$T/out-tmp" -maxdepth 1 \( -name 'sbom-root-*' -o -name 'sbom-drop-*' \))"

echo "== refusals"
mkdir -p "$T/no-record"
cp "$DEBS/pwsh_7.5.1-1_aarch64.deb" "$T/no-record/"
refuse 'build.json is missing' "a package without its build record" sboms "$T/no-record" no-record
mkdir -p "$T/empty"
refuse 'no .deb files' "no package" sboms "$T/empty" empty
printf '%s\n' pwsh_7.5.1-1_aarch64.syft.spdx3.json > "$T/invalid"
refuse 'did not validate' "an SBOM the SPDX validator rejects" sboms "$DEBS" rejected
rm "$T/invalid"
touch "$T/msft-fails"
refuse "the Microsoft SBOM tool's validation: Failure" "a failed Microsoft validation" sboms "$DEBS" msft
rm "$T/msft-fails"

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
