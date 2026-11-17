#!/usr/bin/env bash
# Sign an apt index in a job that never sees a .deb, and install the
# signatures in the job that does.
#
# Usage: sign-release.sh sign <in-dir> <out-dir>
#        sign-release.sh install <signed-dir> <repo-dir>
# Env:   SIGN_KEY             (sign) the online key's id or fingerprint
#        GPG_PASSPHRASE_FILE  (sign) its passphrase file, as for build-repo.sh
#        KEYRING_DEB_SHA256   the SHA-256 of the pwsh-termux-keyring .deb, as
#                             its build provenance was verified (update.yaml's
#                             verify job). Required.
#        VERIFIED_DEB_SHA256S the SHA-256 of every .deb of the build, one per
#                             line, as each one's build provenance was verified
#                             (the verify job). Packages must list exactly
#                             these files, no other. Required.
#        KEYRING_FILE         TEST ONLY: the keyring instead of keys/
#
#   sign     <in-dir> holds Release and Packages, as build-repo.sh (unsigned)
#            wrote them. Fails closed unless the keyring file passes
#            check-keys.sh; SIGN_KEY is its online key and not the recovery
#            key, whose secret is not in this gpg home at all; Release's
#            window is well formed and fresh (written within the last day);
#            Release lists this Packages file by its SHA-256; and Packages
#            holds exactly one keyring package, with KEYRING_DEB_SHA256, and
#            lists exactly the files of VERIFIED_DEB_SHA256S. It
#            writes InRelease and Release.gpg to <out-dir> and checks them
#            with gpgv against the keyring file, as apt will.
#   install  <signed-dir> holds Release, InRelease and Release.gpg. <repo-dir>
#            is an unsigned repository from build-repo.sh. Fails closed
#            unless <repo-dir>'s index files are the ones Release lists, its
#            Packages holds the keyring package with KEYRING_DEB_SHA256, and
#            both signatures verify with gpgv against the keyring file. Then
#            it replaces the repository's Release with the signed one and
#            adds the two signatures.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}
readonly MAX_RELEASE_AGE_SECONDS=$SECONDS_PER_DAY
INDEX_SUBDIR=$(repo_index_subdir)
readonly INDEX_SUBDIR

# keyring_stanza_sha256 <Packages>: the SHA256 field of the keyring package's
# stanza; dies unless there is exactly one.
keyring_stanza_sha256() {
  local sums
  sums=$(awk -v pkg="$KEYRING_PACKAGE" '
    BEGIN { RS = ""; FS = "\n" }
    { name = ""; sum = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Package:[ \t]/) { name = $i; sub(/^Package:[ \t]*/, "", name) }
        if ($i ~ /^SHA256:[ \t]/) { sum = $i; sub(/^SHA256:[ \t]*/, "", sum) }
      }
      if (name == pkg) print (sum == "" ? "missing" : sum) }' "$1")
  [ "$(grep -c . <<<"$sums")" -eq 1 ] || die "$1 does not hold exactly one $KEYRING_PACKAGE package"
  printf '%s\n' "$sums"
}

# stanza_sha256s <Packages>: the SHA256 field of every stanza, one per line
# ("missing" for a stanza without one).
stanza_sha256s() {
  awk '
    BEGIN { RS = ""; FS = "\n" }
    { sum = ""
      for (i = 1; i <= NF; i++) if ($i ~ /^SHA256:[ \t]/) { sum = $i; sub(/^SHA256:[ \t]*/, "", sum) }
      print (sum == "" ? "missing" : sum) }' "$1"
}

# check_index_is_verified <Packages>: every package in it is a file whose
# build provenance was verified, and the keyring package is the one
# KEYRING_DEB_SHA256 names.
check_index_is_verified() {
  local listed verified
  [ -n "${VERIFIED_DEB_SHA256S:-}" ] \
    || die "VERIFIED_DEB_SHA256S (the attestation-verified digests of every .deb) is not set"
  verified=$(LC_ALL=C sort <<<"$VERIFIED_DEB_SHA256S")
  ! grep -qvE '^[0-9a-f]{64}$' <<<"$verified" || die "VERIFIED_DEB_SHA256S is not a list of SHA-256 digests"
  listed=$(stanza_sha256s "$1" | LC_ALL=C sort)
  [ "$listed" = "$verified" ] \
    || die "$1 does not list exactly the .deb files whose provenance was verified (VERIFIED_DEB_SHA256S)"

  [[ "${KEYRING_DEB_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] \
    || die "KEYRING_DEB_SHA256 (the attestation-verified digest of the keyring package) is not set"
  [ "$(keyring_stanza_sha256 "$1")" = "$KEYRING_DEB_SHA256" ] \
    || die "the $KEYRING_PACKAGE in $1 is not the file whose provenance was verified (KEYRING_DEB_SHA256)"
}

# release_lists <Release> <index-dir>: every index file Release lists is
# there with that SHA-256 and size, and Packages is among them.
check_release_lists() {
  local release=$1 base=$2 sum size path seen=0
  while read -r sum size path; do
    [ -f "$base/$path" ] || die "$release lists $path, which is not there"
    [ "$(sha256_of "$base/$path")" = "$sum" ] && [ "$(file_size "$base/$path")" = "$size" ] \
      || die "$path is not the file $release lists"
    [ "$path" = "$INDEX_SUBDIR/Packages" ] && seen=1
  done < <(awk '$0 == "SHA256:" {on = 1; next} on && /^ / {print $1, $2, $3; next} {on = 0}' "$release")
  [ "$seen" -eq 1 ] || die "$release does not list $INDEX_SUBDIR/Packages"
}

check_signing_key() {
  local key_roles online recovery sign_fpr
  key_roles=$(check_keyring "$KEYRING_FILE")
  online=$(online_fingerprints <<<"$key_roles")
  recovery=$(fingerprints_with_role "$ROLE_RECOVERY" <<<"$key_roles")
  sign_fpr=$(secret_key_fingerprint "$SIGN_KEY")
  [ -n "$sign_fpr" ] || die "no secret key for SIGN_KEY in the keyring"
  [ "$sign_fpr" != "$recovery" ] || die "refusing to sign with the recovery key $recovery: it is offline only"
  if [ -n "$recovery" ] && gpg --batch --list-secret-keys -- "$recovery" >/dev/null 2>&1; then
    die "the secret of the recovery key $recovery is in this gpg home; it must never be where the online key is"
  fi
  grep -qx -- "$sign_fpr" <<<"$online" \
    || die "the signing key $sign_fpr is not the online key in $KEYRING_FILE ($(tr '\n' ' ' <<<"$online"))"
  log "signing key $sign_fpr is the key in $KEYRING_FILE"
}

verify_signatures() {
  local dir=$1 keyring
  keyring=$(realpath "$KEYRING_FILE")
  gpgv_quiet "$keyring" "$dir/InRelease" || die "InRelease does not verify against $KEYRING_FILE"
  gpgv_quiet "$keyring" "$dir/Release.gpg" "$dir/Release" || die "Release.gpg does not verify against $KEYRING_FILE"
}

sign_index() {
  local in=$1 out=$2 date
  local -a gpg_options
  [ -n "${SIGN_KEY:-}" ] || die "SIGN_KEY is not set"
  [ -f "$in/Release" ] && [ -f "$in/Packages" ] || die "$in needs Release and Packages"
  check_signing_key
  check_release_window "$in/Release" "$((VALID_UNTIL_DAYS - 1))"
  date=$(release_field_epoch "$in/Release" Date)
  [ $(($(now_epoch) - date)) -le "$MAX_RELEASE_AGE_SECONDS" ] || die "$in/Release was written more than a day ago"
  # Release lists Packages by digest and size; only that file is here.
  [ "$(awk -v p="$INDEX_SUBDIR/Packages" '$0 == "SHA256:" {on = 1; next} on && /^ / {if ($3 == p) print $1, $2; next} {on = 0}' "$in/Release")" = "$(sha256_of "$in/Packages") $(file_size "$in/Packages")" ] \
    || die "$in/Release does not list this Packages file"
  check_index_is_verified "$in/Packages"
  mkdir -p "$out"
  cp "$in/Release" "$out/Release"
  online_gpg_options gpg_options
  sign_release "$out" "${gpg_options[@]}"
  verify_signatures "$out"
  log "signed Release (valid until $(release_field "$out/Release" Valid-Until)) and checked it against $KEYRING_FILE"
}

install_signatures() {
  local signed=$1 repo=$2 dist index
  dist=$(repo_dist_dir "$repo")
  index=$dist/$INDEX_SUBDIR
  [ -f "$signed/Release" ] && [ -f "$signed/InRelease" ] && [ -f "$signed/Release.gpg" ] \
    || die "$signed needs Release, InRelease and Release.gpg"
  verify_signatures "$signed"
  check_release_window "$signed/Release" "$((VALID_UNTIL_DAYS - 1))"
  check_release_lists "$signed/Release" "$dist"
  check_index_is_verified "$index/Packages"
  # InRelease is the clearsigned Release: same text.
  gpg --batch --no-default-keyring --keyring "$(realpath "$KEYRING_FILE")" --decrypt "$signed/InRelease" 2>/dev/null \
    | cmp -s - "$signed/Release" || die "InRelease is not the signed Release"
  cp "$signed/Release" "$signed/InRelease" "$signed/Release.gpg" "$dist/"
  log "installed the signed Release in $repo"
}

case "${1:-} $#" in
  "sign 3") sign_index "$2" "$3" ;;
  "install 3") install_signatures "$2" "$3" ;;
  *) die "usage: sign-release.sh sign <in-dir> <out-dir> | install <signed-dir> <repo-dir>" ;;
esac
