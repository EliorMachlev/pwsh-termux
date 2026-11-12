#!/usr/bin/env bash
# Write the SBOMs of every .deb in a folder: CycloneDX 1.6 and three SPDX
# files, each from a different generator at the highest version it writes.
#
#   <pkg>_<ver>_aarch64.cdx.json          CycloneDX 1.6   Syft, over the package's files
#   <pkg>_<ver>_aarch64.build.spdx.json   SPDX 2.3        the packaging view (spdx-build-view.py)
#   <pkg>_<ver>_aarch64.syft.spdx3.json   SPDX 3.0.1      Syft, over the package's files
#   <pkg>_<ver>_aarch64.msft.spdx3.json   SPDX 3.0        Microsoft's SBOM tool, over the package's files
#
# Usage: make-sboms.sh <debs-dir> <out-dir>
# Needs: dpkg-deb, python3, java, curl, and network access to download the
# tools (each pinned to a version and a SHA-256, checked before use).
set -euo pipefail

DEBS=${1:?debs directory}
OUT=${2:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=${RUNNER_TEMP:-$(mktemp -d)}
tools="$TMP/sbom-tools"
mkdir -p "$tools" "$OUT"

# Pinned: version and the SHA-256 of the download (the same tools and hashes
# CurrenciX uses; tools-java is confirmed by Maven Central's .sha1, Syft by
# its checksums.txt, the SBOM tool publishes none).
SPDX_TOOLS_VERSION=2.0.7
SPDX_TOOLS_SHA256=bf99a8b2ffbea238c1451c6b4be568870f18b4aac93d0dbff755f2b0b7ce43f3
SYFT_VERSION=1.54.0
SYFT_SHA256=54a87372498168b2d033e876fd41fa4e8035b872699e525a57046e1f2f09c860
MS_SBOM_TOOL_VERSION=4.1.5
MS_SBOM_TOOL_SHA256=bf5d4f99bc98c119d549d08fc02ae92598a7a42772f17317c01031a92632e05b

fetch() {
  curl -fsSL --retry 6 --retry-delay 10 --retry-all-errors -o "$3" "$1"
  echo "$2  $3" | sha256sum -c -
}
fetch "https://repo1.maven.org/maven2/org/spdx/tools-java/$SPDX_TOOLS_VERSION/tools-java-$SPDX_TOOLS_VERSION-jar-with-dependencies.jar" "$SPDX_TOOLS_SHA256" "$tools/tools-java.jar"
fetch "https://github.com/anchore/syft/releases/download/v$SYFT_VERSION/syft_${SYFT_VERSION}_linux_amd64.tar.gz" "$SYFT_SHA256" "$tools/syft.tar.gz"
tar -xzf "$tools/syft.tar.gz" -C "$tools" syft
fetch "https://github.com/microsoft/sbom-tool/releases/download/v$MS_SBOM_TOOL_VERSION/sbom-tool-linux-x64" "$MS_SBOM_TOOL_SHA256" "$tools/sbom-tool"
chmod +x "$tools/sbom-tool"

shopt -s nullglob
debs=("$DEBS"/*.deb)
[ "${#debs[@]}" -gt 0 ] || { echo "no .deb files in $DEBS" >&2; exit 1; }

for deb in "${debs[@]}"; do
  base=$(basename "${deb%.deb}")
  record="${deb%.deb}.build.json"
  [ -f "$record" ] || { echo "::error::$record is missing" >&2; exit 1; }
  pkgname=$(dpkg-deb -f "$deb" Package)
  pkgver=$(dpkg-deb -f "$deb" Version)
  echo "SBOMs for $base" >&2

  root="$TMP/sbom-root-$base"
  rm -rf "$root"; mkdir -p "$root"
  dpkg-deb -x "$deb" "$root"

  # 1. CycloneDX 1.6 (Syft, the package's files).
  "$tools/syft" "dir:$root" -o "cyclonedx-json@1.6=$OUT/$base.cdx.json" -q

  # 2. SPDX 2.3: the packaging view.
  python3 "$HERE/spdx-build-view.py" "$deb" "$record" "$OUT/$base.build.spdx.json"

  # 3. SPDX 3.0.1 (Syft, the package's files).
  "$tools/syft" "dir:$root" -o "spdx-json@3.0=$OUT/$base.syft.spdx3.json" -q

  # 4. SPDX 3.0 (Microsoft's SBOM tool).
  drop="$TMP/sbom-drop-$base"
  rm -rf "$drop"; mkdir -p "$drop"
  "$tools/sbom-tool" generate -b "$root" -bc "$root" -pn "$pkgname" -pv "$pkgver" -ps "pwsh-termux" \
    -m "$drop" -nsb "https://github.com/EliorMachlev/pwsh-termux/spdx" -mi SPDX:3.0 -V Error
  cp "$drop/_manifest/spdx_3.0/manifest.spdx.json" "$OUT/$base.msft.spdx3.json"

  # Each file is validated: the SPDX project's validator for the 2.3 and
  # Syft files; the Microsoft tool's own `validate` for its SPDX 3.0 file
  # (tools-java does not accept that tool's output).
  for f in "$OUT/$base.build.spdx.json" "$OUT/$base.syft.spdx3.json"; do
    java -jar "$tools/tools-java.jar" Verify "$f" 2>&1 | tee "$TMP/verify.log"
    grep -q 'This SPDX Document is valid.' "$TMP/verify.log" \
      || { echo "::error::$f did not validate" >&2; exit 1; }
  done
  "$tools/sbom-tool" validate -b "$root" -m "$drop" -o "$TMP/msft-validation.json" -mi SPDX:3.0 -V Error
  python3 - "$TMP/msft-validation.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
if r["Result"] != "Success":
    sys.exit(f"::error::the Microsoft SBOM tool's validation: {r['Result']}; {r.get('ValidationErrors')}")
PY
  rm -rf "$root" "$drop"
done
ls -l "$OUT" >&2
