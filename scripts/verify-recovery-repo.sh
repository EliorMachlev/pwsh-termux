#!/usr/bin/env bash
# Verify a repository signed with the offline RECOVERY key (recovery-sign.sh)
# before it is deployed: used by recovery-sign.sh on the maintainer's machine
# and by .github/workflows/recover.yaml, which has no signing key at all.
#
# Usage: verify-recovery-repo.sh <repo-dir>
# Env:   KEYRING_FILE  TEST ONLY: instead of keys/pwsh-termux-archive-keyring.gpg
#
# Fails unless:
#   - keys/ passes check-keys.sh and keys/RECOVERY names a recovery key;
#   - InRelease and Release.gpg verify with gpgv against the recovery key
#     ALONE, and InRelease's signed text is the Release file;
#   - Release has a Date that is not in the future and a Valid-Until at most
#     VALID_UNTIL_DAYS (14) days after it, with at least VALID_UNTIL_WARN_DAYS
#     (7) days still left (scripts/lib/common.sh): the recovery key never
#     makes an unbounded index, and a nearly expired one is not deployed;
#   - every index file's SHA-256 matches Release, every .deb in pool/ is
#     listed in Packages with a matching SHA-256, and nothing else is in pool/;
#   - pwsh-termux.gpg is keys/pwsh-termux-archive-keyring.gpg byte for byte,
#     and pwsh-termux-keyring.deb is listed in Packages and ships that file.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

REPO_DIR=${1:?repository folder}
KEYRING_FILE=${KEYRING_FILE:-$SCRIPTS_DIR/../keys/$KEYRING_BASENAME}
DIST_DIR=$(repo_dist_dir "$REPO_DIR")
INDEX_SUBDIR=$(repo_index_subdir)
PACKAGES_FILE=$DIST_DIR/$INDEX_SUBDIR/Packages
KEY_FILE=$(repo_key_file "$REPO_DIR")
KEYRING_DEB=$(repo_keyring_deb "$REPO_DIR")
readonly DIST_DIR INDEX_SUBDIR PACKAGES_FILE KEY_FILE KEYRING_DEB

# Removed on exit.
WORK_DIR=

require_repo_files() {
  local path
  for path in "$DIST_DIR/Release" "$DIST_DIR/InRelease" "$DIST_DIR/Release.gpg" "$KEY_FILE" "$KEYRING_DEB"; do
    [ -f "$path" ] && [ ! -L "$path" ] || die "missing or not a regular file: $path"
  done
}

# export_recovery_key <fingerprint> <out-file>: a keyring with the recovery
# key only, from the keyring file.
export_recovery_key() {
  local recovery=$1 out_file=$2
  mkdir -m 700 "$WORK_DIR/gnupg"
  gpg --batch --homedir "$WORK_DIR/gnupg" --import "$KEYRING_FILE" 2>/dev/null
  gpg --batch --homedir "$WORK_DIR/gnupg" --export -- "$recovery" > "$out_file"
  [ -s "$out_file" ] || die "could not export the recovery key $recovery"
}

# verify_signatures <fingerprint> <recovery-keyring>: InRelease and
# Release.gpg are the recovery key's signatures of Release.
verify_signatures() {
  local recovery=$1 recovery_keyring=$2
  gpgv_quiet "$recovery_keyring" --output - "$DIST_DIR/InRelease" > "$WORK_DIR/inrelease.txt" \
    || die "InRelease is not signed by the recovery key $recovery"
  gpgv_quiet "$recovery_keyring" "$DIST_DIR/Release.gpg" "$DIST_DIR/Release" \
    || die "Release.gpg is not a signature of Release by the recovery key $recovery"
  cmp -s "$WORK_DIR/inrelease.txt" "$DIST_DIR/Release" || die "InRelease does not sign the same text as Release"
}

# Release -> index files.
verify_index_files() {
  local listed=0 sha size path index_file
  while read -r sha size path; do
    index_file="$DIST_DIR/$path"
    [ -f "$index_file" ] || die "Release lists $path, which is missing"
    [ "$(sha256_of "$index_file")" = "$sha" ] && [ "$(file_size "$index_file")" = "$size" ] \
      || die "$path does not match Release"
    listed=$((listed + 1))
  done < <(awk '/^SHA256:/ {on = 1; next} /^[^ ]/ {on = 0} on {print $1, $2, $3}' "$DIST_DIR/Release")
  [ "$listed" -gt 0 ] || die "Release lists no index files"
  grep -q " $INDEX_SUBDIR/Packages$" "$DIST_DIR/Release" || die "Release does not list $PACKAGES_FILE"
}

# Packages -> every .deb in pool/, and nothing else.
verify_pool() {
  local pool_path sha
  awk '/^Filename: / {f = $2} /^SHA256: / {print f, $2}' "$PACKAGES_FILE" > "$WORK_DIR/debs.txt"
  while read -r pool_path sha; do
    [ -f "$REPO_DIR/$pool_path" ] || die "Packages lists $pool_path, which is missing"
    [ "$(sha256_of "$REPO_DIR/$pool_path")" = "$sha" ] || die "$pool_path does not match Packages"
  done < "$WORK_DIR/debs.txt"
  ( cd "$REPO_DIR" && find pool -type f -o -type l ) | sort > "$WORK_DIR/pool.txt"
  cut -d' ' -f1 "$WORK_DIR/debs.txt" | sort > "$WORK_DIR/listed.txt"
  cmp -s "$WORK_DIR/pool.txt" "$WORK_DIR/listed.txt" || die "pool/ holds files that Packages does not list"
}

# The key files: the keyring file, and a listed keyring package that ships it.
verify_key_files() {
  cmp -s "$KEY_FILE" "$KEYRING_FILE" || die "$PUBLISHED_KEY_GPG is not $KEYRING_FILE"
  cut -d' ' -f2 "$WORK_DIR/debs.txt" | grep -qx "$(sha256_of "$KEYRING_DEB")" \
    || die "$PUBLISHED_KEYRING_DEB is not a package listed in Packages"
  deb_ships_keyring "$KEYRING_DEB" "$KEYRING_FILE" \
    || die "$PUBLISHED_KEYRING_DEB does not ship $KEYRING_FILE"
}

main() {
  local recovery
  recovery=$(require_recovery_fingerprint "$KEYRING_FILE")
  require_repo_files

  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  export_recovery_key "$recovery" "$WORK_DIR/recovery.gpg"
  verify_signatures "$recovery" "$WORK_DIR/recovery.gpg"
  check_release_fresh "$DIST_DIR/Release"
  verify_index_files
  verify_pool
  verify_key_files

  log "signed by the recovery key $recovery, valid until $(release_field "$DIST_DIR/Release" Valid-Until); index, pool and key files consistent"
}

main
