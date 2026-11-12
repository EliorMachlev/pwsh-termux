#!/usr/bin/env bash
# Check the repository's public keyring and print its key fingerprints.
# keys/pwsh-termux-archive-keyring.gpg is committed to Git and shipped in
# pwsh-termux-keyring, so every key in it is trusted by users for this
# repository, and a secret key in it would be published.
#
# Usage: check-keys.sh [keyring-file]
#   (default: keys/pwsh-termux-archive-keyring.gpg, and then keys/ may hold
#   nothing but that file and ROTATION)
#
# The rules, all fail closed:
#   - binary OpenPGP (not armored), readable, no secret key material;
#   - no ROTATION file next to the keyring (steady state): exactly one
#     primary key;
#   - a ROTATION file (a planned rotation is in progress; one line, the
#     40-hex fingerprint of the next key): exactly two primary keys, and one
#     of them is the key it names. A ROTATION file with one key is stale.
# Which of the keys may sign is build-repo.sh's check (it knows the signer).
#
# Prints one line per primary key on stdout: <fingerprint> <role>, where role
# is "key" (steady state), or "current" / "next" (during a rotation).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEFAULT=$ROOT/keys/pwsh-termux-archive-keyring.gpg
FILE=${1:-$DEFAULT}
MARKER=$(dirname "$FILE")/ROTATION

log() { printf '[check-keys] %s\n' "$*" >&2; }
die() { printf '[check-keys] ERROR: %s\n' "$*" >&2; exit 1; }

if [ "$FILE" -ef "$DEFAULT" ]; then
  shopt -s nullglob dotglob
  for f in "$ROOT/keys"/*; do
    case $(basename "$f") in
      pwsh-termux-archive-keyring.gpg|ROTATION) ;;
      *) die "keys/ holds an unexpected file: $(basename "$f")" ;;
    esac
  done
fi

[ -f "$FILE" ] || die "$FILE is not a regular file"
[ -s "$FILE" ] || die "$FILE is empty"
# apt reads a signed-by .gpg file as binary OpenPGP; an armored file needs
# the .asc extension, which this repository does not use.
[ "$(head -c 5 "$FILE")" != "-----" ] || die "$FILE is armored; it must be binary OpenPGP (gpg --dearmor)"
packets=$(gpg --batch --list-packets "$FILE" 2>/dev/null) || die "$FILE is not a readable OpenPGP file"
if grep -q '^:secret' <<<"$packets"; then
  die "$FILE contains secret key material; remove it from the tree and rotate the key"
fi

# Primary keys: the fpr line that follows each pub line (not a subkey's).
mapfile -t fprs < <(gpg --batch --show-keys --with-colons "$FILE" 2>/dev/null \
  | awk -F: '$1 == "pub" {want = 1; next} $1 == "fpr" && want {print $10; want = 0}')

if [ ! -e "$MARKER" ]; then
  [ "${#fprs[@]}" -eq 1 ] \
    || die "$FILE holds ${#fprs[@]} primary keys; without a ROTATION file it must hold exactly one, the signing key"
  printf '%s key\n' "${fprs[0]}"
  log "one public key (steady state)"
  exit 0
fi

[ -f "$MARKER" ] || die "$MARKER is not a regular file"
[ "$(wc -l < "$MARKER")" -eq 1 ] || die "$MARKER must be one line: the next key's fingerprint"
next=$(tr -d '[:space:]' < "$MARKER")
[[ "$next" =~ ^[0-9A-F]{40}$ ]] || die "$MARKER does not hold a fingerprint (40 upper-case hex digits)"
[ "${#fprs[@]}" -eq 2 ] \
  || die "$MARKER is present, so $FILE must hold exactly two primary keys (current and next), not ${#fprs[@]}; remove ROTATION when the old key is dropped"
found=0
for f in "${fprs[@]}"; do
  if [ "$f" = "$next" ]; then
    printf '%s next\n' "$f"; found=1
  else
    printf '%s current\n' "$f"
  fi
done
[ "$found" -eq 1 ] || die "$MARKER names $next, which is not one of the two keys in $FILE"
log "two public keys (rotation to $next in progress)"
