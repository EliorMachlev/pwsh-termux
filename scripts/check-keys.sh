#!/usr/bin/env bash
# Check the repository's public keyring and print its key fingerprints.
# keys/pwsh-termux-archive-keyring.gpg is committed to Git and shipped in
# pwsh-termux-keyring, so every key in it is trusted by users for this
# repository, and a secret key in it would be published.
#
# Usage: check-keys.sh [keyring-file]
#   (default: keys/pwsh-termux-archive-keyring.gpg; keys/ may then hold
#   nothing but that file, RECOVERY and ROTATION). The two marker files are
#   read from the keyring file's folder.
#
# The keyring holds, as primary keys:
#   - exactly one CURRENT online key (the one GitHub Actions signs with);
#   - the RECOVERY key if, and only if, keys/RECOVERY names it (one line, its
#     40-hex fingerprint): an offline key the maintainer holds, never in CI;
#   - the NEXT online key if, and only if, keys/ROTATION names it (a planned
#     rotation is in progress); it is neither the current nor the recovery key.
# So the allowed shapes are {current}, {current, recovery}, {current, next}
# and {current, next, recovery}; anything else fails. A ROTATION marker whose
# key is the only online key left is stale and fails too.
# Which online key may sign, and that the recovery key never does, is
# build-repo.sh's check (it knows the signer).
#
# Prints one line per primary key on stdout: <fingerprint> <role>, role being
# current, next or recovery. Also binary OpenPGP only, no secret material.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEFAULT=$ROOT/keys/pwsh-termux-archive-keyring.gpg
FILE=${1:-$DEFAULT}
DIR=$(dirname "$FILE")

log() { printf '[check-keys] %s\n' "$*" >&2; }
die() { printf '[check-keys] ERROR: %s\n' "$*" >&2; exit 1; }

if [ "$FILE" -ef "$DEFAULT" ]; then
  shopt -s nullglob dotglob
  for f in "$ROOT/keys"/*; do
    case $(basename "$f") in
      pwsh-termux-archive-keyring.gpg|RECOVERY|ROTATION) ;;
      *) die "keys/ holds an unexpected file: $(basename "$f")" ;;
    esac
  done
fi

# marker <name>: the fingerprint in $DIR/<name>, or nothing if it is absent.
marker() {
  local m="$DIR/$1"
  [ -e "$m" ] || return 0
  [ -f "$m" ] || die "$m is not a regular file"
  [ "$(wc -l < "$m")" -eq 1 ] || die "$m must be one line: a fingerprint"
  local fpr
  fpr=$(tr -d '[:space:]' < "$m")
  [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || die "$m does not hold a fingerprint (40 upper-case hex digits)"
  printf '%s\n' "$fpr"
}
recovery=$(marker RECOVERY)
next=$(marker ROTATION)

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

has() { local f; for f in "${fprs[@]}"; do [ "$f" = "$1" ] && return 0; done; return 1; }
if [ -n "$recovery" ]; then
  has "$recovery" || die "keys/RECOVERY names $recovery, which is not in $FILE"
fi
if [ -n "$next" ]; then
  [ "$next" != "$recovery" ] || die "keys/ROTATION and keys/RECOVERY name the same key; the recovery key is never an online key"
  has "$next" || die "keys/ROTATION names $next, which is not in $FILE"
fi

current=()
for f in "${fprs[@]}"; do
  if [ "$f" != "$recovery" ] && [ "$f" != "$next" ]; then current+=("$f"); fi
done
if [ "${#current[@]}" -ne 1 ]; then
  if [ -n "$next" ] && [ "${#current[@]}" -eq 0 ]; then
    die "keys/ROTATION is stale: $next is the only online key left; remove keys/ROTATION"
  fi
  die "$FILE must hold exactly one current online key besides the keys named in keys/RECOVERY and keys/ROTATION; it holds ${#current[@]} (${#fprs[@]} keys in all)"
fi

printf '%s current\n' "${current[0]}"
[ -z "$next" ] || printf '%s next\n' "$next"
[ -z "$recovery" ] || printf '%s recovery\n' "$recovery"
log "${#fprs[@]} public key(s): current${next:+, next}${recovery:+, recovery}"
