#!/usr/bin/env bash
# Verify a file's build provenance: it must have been built by this
# repository's build-packages.yaml, from the given commit, on a GitHub-hosted
# runner. Prints the file's SHA-256 on stdout when it verifies.
#
# Usage: verify-attestation.sh <file> <commit-sha>
# Needs: gh, with GH_TOKEN set (read access is enough). Run it where the apt
# signing key is not: update.yaml does, in its own job.
set -euo pipefail

FILE=${1:?file to verify}
COMMIT=${2:?commit the file must have been built from}
REPO=EliorMachlev/pwsh-termux
SIGNER=$REPO/.github/workflows/build-packages.yaml

die() { printf '[verify-attestation] ERROR: %s\n' "$*" >&2; exit 1; }

[ -f "$FILE" ] || die "$FILE not found"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "not a commit SHA: $COMMIT"

gh attestation verify "$FILE" --repo "$REPO" --signer-workflow "$SIGNER" \
  --source-digest "$COMMIT" --deny-self-hosted-runners >&2 \
  || die "$FILE has no valid provenance from $SIGNER at $COMMIT"
sha256sum < "$FILE" | cut -d' ' -f1
