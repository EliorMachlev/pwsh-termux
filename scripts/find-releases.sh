#!/usr/bin/env bash
# Print the PowerShell releases to package, one per line:
#   stable <tag>
#   preview <tag>      (only if it is newer than the newest stable)
#
# Microsoft backports patch releases for older lines (e.g. v7.4.x) after newer
# lines ship, so "newest by date" is wrong; we pick the highest version instead.
# Tags without a linux-arm64 tarball (release still being uploaded) are skipped.
set -euo pipefail

API="https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=50"
auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

json=$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "$API")

pick() { # $1 = true|false (prerelease flag)
  jq -r --argjson pre "$1" '
    .[] | select(.draft == false and .prerelease == $pre)
        | select(any(.assets[]; .name | test("^powershell-.*-linux-arm64\\.tar\\.gz$")))
        | .tag_name' <<<"$json" | sort -V | tail -n1
}

stable=$(pick false)
preview=$(pick true)
[ -n "$stable" ] || { echo "no stable release found" >&2; exit 1; }
echo "stable $stable"

if [ -n "$preview" ]; then
  core() { local v=${1#v}; echo "${v%%-*}"; }
  newest=$(printf '%s\n%s\n' "$(core "$stable")" "$(core "$preview")" | sort -V | tail -n1)
  # preview is only interesting if its core version is strictly newer than stable
  if [ "$(core "$preview")" != "$(core "$stable")" ] && [ "$newest" = "$(core "$preview")" ]; then
    echo "preview $preview"
  fi
fi
