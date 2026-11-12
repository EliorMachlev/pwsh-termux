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
source "$(dirname "$0")/lib/common.sh"

# The production keys/ folder holds the keyring file and the markers only.
require_only_allowed_files_in_keys_dir() {
  local path
  shopt -s nullglob dotglob
  for path in "$KEYS_DIR"/*; do
    is_allowed_in_keys_dir "$(basename "$path")" \
      || die "keys/ holds an unexpected file: $(basename "$path")"
  done
}

# require_binary_public_keyring <file>: a non-empty, binary OpenPGP file with
# no secret key material.
require_binary_public_keyring() {
  local keyring_file=$1 packets
  [ -f "$keyring_file" ] || die "$keyring_file is not a regular file"
  [ -s "$keyring_file" ] || die "$keyring_file is empty"
  # apt reads a signed-by .gpg file as binary OpenPGP; an armored file needs
  # the .asc extension, which this repository does not use.
  [ "$(head -c 5 "$keyring_file")" != "-----" ] \
    || die "$keyring_file is armored; it must be binary OpenPGP (gpg --dearmor)"
  packets=$(gpg --batch --list-packets "$keyring_file" 2>/dev/null) \
    || die "$keyring_file is not a readable OpenPGP file"
  if grep -q '^:secret' <<<"$packets"; then
    die "$keyring_file contains secret key material; remove it from the tree and rotate the key"
  fi
}

# contains <needle> <item...>: true if the needle is one of the items.
contains() {
  local needle=$1 item; shift
  for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
  return 1
}

main() {
  local keyring_file=${1:-$DEFAULT_KEYRING_FILE}
  local marker_dir recovery next
  local -a fingerprints current
  marker_dir=$(dirname "$keyring_file")

  if is_production_keyring "$keyring_file"; then
    require_only_allowed_files_in_keys_dir
  fi
  recovery=$(read_fingerprint_marker "$marker_dir/$MARKER_RECOVERY")
  next=$(read_fingerprint_marker "$marker_dir/$MARKER_ROTATION")

  require_binary_public_keyring "$keyring_file"
  mapfile -t fingerprints < <(primary_fingerprints "$keyring_file")

  if [ -n "$recovery" ]; then
    contains "$recovery" "${fingerprints[@]}" \
      || die "keys/$MARKER_RECOVERY names $recovery, which is not in $keyring_file"
  fi
  if [ -n "$next" ]; then
    [ "$next" != "$recovery" ] \
      || die "keys/$MARKER_ROTATION and keys/$MARKER_RECOVERY name the same key; the recovery key is never an online key"
    contains "$next" "${fingerprints[@]}" \
      || die "keys/$MARKER_ROTATION names $next, which is not in $keyring_file"
  fi

  # The current key: every key that no marker names. There must be one.
  current=()
  local fingerprint
  for fingerprint in "${fingerprints[@]}"; do
    if [ "$fingerprint" != "$recovery" ] && [ "$fingerprint" != "$next" ]; then
      current+=("$fingerprint")
    fi
  done
  if [ "${#current[@]}" -ne 1 ]; then
    if [ -n "$next" ] && [ "${#current[@]}" -eq 0 ]; then
      die "keys/$MARKER_ROTATION is stale: $next is the only online key left; remove keys/$MARKER_ROTATION"
    fi
    die "$keyring_file must hold exactly one current online key besides the keys named in keys/$MARKER_RECOVERY and keys/$MARKER_ROTATION; it holds ${#current[@]} (${#fingerprints[@]} keys in all)"
  fi

  printf '%s %s\n' "${current[0]}" "$ROLE_CURRENT"
  [ -z "$next" ] || printf '%s %s\n' "$next" "$ROLE_NEXT"
  [ -z "$recovery" ] || printf '%s %s\n' "$recovery" "$ROLE_RECOVERY"
  log "${#fingerprints[@]} public key(s): $ROLE_CURRENT${next:+, $ROLE_NEXT}${recovery:+, $ROLE_RECOVERY}"
}

main "$@"
