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
source "$(dirname "$0")/lib/common.sh"

DEBS_DIR=${1:?debs directory}
OUT_DIR=${2:?output directory}
TMP=${RUNNER_TEMP:-$(mktemp -d)}
TOOLS_DIR="$TMP/sbom-tools"

# Pinned: version and the SHA-256 of the download (the same tools and hashes
# CurrenciX uses; tools-java is confirmed by Maven Central's .sha1, Syft by
# its checksums.txt, the SBOM tool publishes none).
readonly SPDX_TOOLS_VERSION=2.0.7
readonly SPDX_TOOLS_SHA256=bf99a8b2ffbea238c1451c6b4be568870f18b4aac93d0dbff755f2b0b7ce43f3
readonly SYFT_VERSION=1.54.0
readonly SYFT_SHA256=54a87372498168b2d033e876fd41fa4e8035b872699e525a57046e1f2f09c860
readonly MS_SBOM_TOOL_VERSION=4.1.5
readonly MS_SBOM_TOOL_SHA256=bf5d4f99bc98c119d549d08fc02ae92598a7a42772f17317c01031a92632e05b

readonly SPDX_NAMESPACE_BASE=https://github.com/EliorMachlev/pwsh-termux/spdx
readonly SPDX_VALID_MESSAGE='This SPDX Document is valid.'

# error <message>: a GitHub Actions error annotation, then exit 1.
error() { echo "::error::$*" >&2; exit "$EXIT_FAILURE"; }

# fetch <url> <sha256> <file>: download, then check the SHA-256.
fetch() {
  curl -fsSL --retry 6 --retry-delay 10 --retry-all-errors -o "$3" "$1"
  echo "$2  $3" | sha256sum -c -
}

install_tools() {
  mkdir -p "$TOOLS_DIR" "$OUT_DIR"
  fetch "https://repo1.maven.org/maven2/org/spdx/tools-java/$SPDX_TOOLS_VERSION/tools-java-$SPDX_TOOLS_VERSION-jar-with-dependencies.jar" "$SPDX_TOOLS_SHA256" "$TOOLS_DIR/tools-java.jar"
  fetch "https://github.com/anchore/syft/releases/download/v$SYFT_VERSION/syft_${SYFT_VERSION}_linux_amd64.tar.gz" "$SYFT_SHA256" "$TOOLS_DIR/syft.tar.gz"
  tar -xzf "$TOOLS_DIR/syft.tar.gz" -C "$TOOLS_DIR" syft
  fetch "https://github.com/microsoft/sbom-tool/releases/download/v$MS_SBOM_TOOL_VERSION/sbom-tool-linux-x64" "$MS_SBOM_TOOL_SHA256" "$TOOLS_DIR/sbom-tool"
  chmod +x "$TOOLS_DIR/sbom-tool"
}

# fresh_dir <dir>: an empty folder at that path.
fresh_dir() { rm -rf "$1"; mkdir -p "$1"; }

# validate_spdx <file>: the SPDX project's validator accepts it.
validate_spdx() {
  java -jar "$TOOLS_DIR/tools-java.jar" Verify "$1" 2>&1 | tee "$TMP/verify.log"
  grep -q "$SPDX_VALID_MESSAGE" "$TMP/verify.log" || error "$1 did not validate"
}

# validate_msft_sbom <root> <drop>: the Microsoft tool's own `validate` (tools-java
# does not accept that tool's output).
validate_msft_sbom() {
  local root=$1 drop=$2
  "$TOOLS_DIR/sbom-tool" validate -b "$root" -m "$drop/_manifest" -o "$TMP/msft-validation.json" -mi SPDX:3.0 -V Error
  python3 - "$TMP/msft-validation.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
if r["Result"] != "Success":
    sys.exit(f"::error::the Microsoft SBOM tool's validation: {r['Result']}; {r.get('ValidationErrors')}")
PY
}

# sboms_for <deb>: the four SBOMs of one package, each validated.
sboms_for() {
  local deb=$1 base record pkgname pkgver root drop spdx_file
  base=$(basename "${deb%.deb}")
  record="${deb%.deb}.build.json"
  [ -f "$record" ] || error "$record is missing"
  pkgname=$(dpkg-deb -f "$deb" Package)
  pkgver=$(dpkg-deb -f "$deb" Version)
  echo "SBOMs for $base" >&2

  root="$TMP/sbom-root-$base"
  fresh_dir "$root"
  dpkg-deb -x "$deb" "$root"

  # 1. CycloneDX 1.6 (Syft, the package's files).
  "$TOOLS_DIR/syft" "dir:$root" -o "cyclonedx-json@1.6=$OUT_DIR/$base.cdx.json" -q

  # 2. SPDX 2.3: the packaging view.
  python3 "$SCRIPTS_DIR/spdx-build-view.py" "$deb" "$record" "$OUT_DIR/$base.build.spdx.json"

  # 3. SPDX 3.0.1 (Syft, the package's files).
  "$TOOLS_DIR/syft" "dir:$root" -o "spdx-json@3.0=$OUT_DIR/$base.syft.spdx3.json" -q

  # 4. SPDX 3.0 (Microsoft's SBOM tool).
  drop="$TMP/sbom-drop-$base"
  fresh_dir "$drop"
  "$TOOLS_DIR/sbom-tool" generate -b "$root" -bc "$root" -pn "$pkgname" -pv "$pkgver" -ps "$PROJECT_NAME" \
    -m "$drop" -nsb "$SPDX_NAMESPACE_BASE" -mi SPDX:3.0 -V Error
  cp "$drop/_manifest/spdx_3.0/manifest.spdx.json" "$OUT_DIR/$base.msft.spdx3.json"

  # Each file is validated: the SPDX project's validator for the 2.3 and
  # Syft files; the Microsoft tool's own for its SPDX 3.0 file.
  for spdx_file in "$OUT_DIR/$base.build.spdx.json" "$OUT_DIR/$base.syft.spdx3.json"; do
    validate_spdx "$spdx_file"
  done
  validate_msft_sbom "$root" "$drop"
  rm -rf "$root" "$drop"
}

main() {
  local -a debs
  local deb
  install_tools

  shopt -s nullglob
  debs=("$DEBS_DIR"/*.deb)
  [ "${#debs[@]}" -gt 0 ] || { echo "no .deb files in $DEBS_DIR" >&2; exit "$EXIT_FAILURE"; }

  for deb in "${debs[@]}"; do
    sboms_for "$deb"
  done
  ls -l "$OUT_DIR" >&2
}

main
