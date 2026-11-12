#!/usr/bin/env bash
# Check that key files hold public OpenPGP keys only, and list their
# fingerprints. keys/ is committed to Git and shipped in pwsh-termux-keyring,
# so a secret key there would be published.
#
# Usage: check-keys.sh [file...]      (default: every file in keys/)
# Prints one line per primary key on stdout: <fingerprint> <file>
# Exits non-zero if a file is armored, unreadable, holds no public key, or
# holds any secret key material.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

log() { printf '[check-keys] %s\n' "$*" >&2; }
die() { printf '[check-keys] ERROR: %s\n' "$*" >&2; exit 1; }

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  shopt -s nullglob dotglob
  files=("$ROOT/keys"/*)
  [ "${#files[@]}" -gt 0 ] || die "keys/ is empty"
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || die "$f is not a regular file"
  [ -s "$f" ] || die "$f is empty"
  # apt reads a signed-by .gpg file as binary OpenPGP; an armored file needs
  # the .asc extension, which this repository does not use.
  [ "$(head -c 5 "$f")" != "-----" ] || die "$f is armored; keys/ holds binary OpenPGP (gpg --dearmor)"
  packets=$(gpg --batch --list-packets "$f" 2>/dev/null) || die "$f is not a readable OpenPGP file"
  if grep -q '^:secret' <<<"$packets"; then
    die "$f contains secret key material; remove it from the tree and rotate the key"
  fi
  grep -q '^:public key packet:' <<<"$packets" || die "$f holds no public key"
  # Primary keys only: the fpr line that follows each pub line.
  gpg --batch --show-keys --with-colons "$f" 2>/dev/null \
    | awk -F: -v file="$f" '$1 == "pub" {want = 1; next}
                            $1 == "fpr" && want {print $10, file; want = 0}'
done
log "${#files[@]} file(s): public keys only"
