#!/usr/bin/env bash
# Print the PowerShell releases to package, one per line:
#   stable <tag>
#   preview <tag>      (only if it is newer than the newest stable)
#
# Microsoft backports patch releases for older lines (e.g. v7.4.x) after newer
# lines ship, so "newest by date" is wrong; we pick the highest version instead.
# Tags without a linux-arm64 tarball (release still being uploaded) are skipped.
set -euo pipefail

readonly RELEASES_API="https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=50"
# The asset build-deb.sh packages; a release without it is still uploading.
readonly ARM64_TARBALL_REGEX='^powershell-.*-linux-arm64\.tar\.gz$'

# fetch_releases: the releases as JSON, authenticated when GITHUB_TOKEN is set.
fetch_releases() {
  local -a auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" "$RELEASES_API"
}

# newest_tag <releases-json> <true|false>: the highest-versioned published
# tag with the arm64 tarball, prereleases or not.
newest_tag() {
  jq -r --argjson pre "$2" --arg tarball "$ARM64_TARBALL_REGEX" '
    .[] | select(.draft == false and .prerelease == $pre)
        | select(any(.assets[]; .name | test($tarball)))
        | .tag_name' <<<"$1" | sort -V | tail -n1
}

# core_version <tag>: v7.6.0-preview.4 -> 7.6.0
core_version() { local v=${1#v}; echo "${v%%-*}"; }

# is_strictly_newer <tag> <than-tag>: compares the core versions only.
is_strictly_newer() {
  local candidate than newest
  candidate=$(core_version "$1")
  than=$(core_version "$2")
  newest=$(printf '%s\n%s\n' "$than" "$candidate" | sort -V | tail -n1)
  [ "$candidate" != "$than" ] && [ "$newest" = "$candidate" ]
}

main() {
  local releases stable preview
  releases=$(fetch_releases)
  stable=$(newest_tag "$releases" false)
  preview=$(newest_tag "$releases" true)
  [ -n "$stable" ] || { echo "no stable release found" >&2; exit 1; }
  echo "stable $stable"

  # preview is only interesting if its core version is strictly newer than stable
  if [ -n "$preview" ] && is_strictly_newer "$preview" "$stable"; then
    echo "preview $preview"
  fi
}

main
