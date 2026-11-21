#!/usr/bin/env bash
# Download a tool and check its SHA-256 before anything uses it: the shared
# download for the workflows' pinned tools (lychee, jactionlint, shfmt). It
# retries as the scripts do (lib/common.sh) and skips the download when the
# file is already there with the right hash.
#
# Usage: fetch-verified.sh <url> <sha256> <file>
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

[ "$#" -eq 3 ] || die "usage: fetch-verified.sh <url> <sha256> <file>"
fetch_verified "$1" "$2" "$3"
