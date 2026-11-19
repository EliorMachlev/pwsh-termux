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
#            Packages holds exactly one keyring package, with
#            KEYRING_DEB_SHA256, and lists exactly the files of
#            VERIFIED_DEB_SHA256S; every stanza has only the fields the build
#            writes (PACKAGES_FIELDS, common.sh), each once; and Release is byte for byte the one
#            write_release (common.sh) writes for this Packages (and its .gz
#            and .xz, which it rebuilds) and Release's Date, so it has no
#            field or section of its own. It writes InRelease and Release.gpg to <out-dir> and checks them
#            with gpgv against the keyring file, as apt will.
#   install  <signed-dir> holds Release, InRelease and Release.gpg. <repo-dir>
#            is an unsigned repository from build-repo.sh. Fails closed
#            unless Release is byte for byte what write_release writes for
#            <repo-dir>'s index files and Release's Date, its Packages holds the keyring package with KEYRING_DEB_SHA256, and
#            both signatures verify with gpgv against the keyring file. Then
#            it replaces the repository's Release with the signed one and
#            adds the two signatures.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}
readonly MAX_RELEASE_AGE_SECONDS=$SECONDS_PER_DAY
INDEX_SUBDIR=$(repo_index_subdir)
readonly INDEX_SUBDIR

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# stanza_digests <Packages>: "<package> <SHA256>" for every stanza ("-" for a
# stanza without a Package field, "missing" for one without a SHA256).
stanza_digests() {
  awk '
    BEGIN { RS = ""; FS = "\n" }
    { name = ""; sum = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Package:[ \t]/) { name = $i; sub(/^Package:[ \t]*/, "", name) }
        if ($i ~ /^SHA256:[ \t]/) { sum = $i; sub(/^SHA256:[ \t]*/, "", sum) }
      }
      print (name == "" ? "-" : name), (sum == "" ? "missing" : sum) }' "$1"
}

# check_index_is_verified <Packages>: every package in it is a file whose
# build provenance was verified, and the keyring package is the one
# KEYRING_DEB_SHA256 names.
check_index_is_verified() {
  local listed verified keyring_sums
  [ -n "${VERIFIED_DEB_SHA256S:-}" ] \
    || die "VERIFIED_DEB_SHA256S (the attestation-verified digests of every .deb) is not set"
  verified=$(LC_ALL=C sort <<<"$VERIFIED_DEB_SHA256S")
  ! grep -qvE '^[0-9a-f]{64}$' <<<"$verified" || die "VERIFIED_DEB_SHA256S is not a list of SHA-256 digests"
  listed=$(stanza_digests "$1")
  [ "$(awk '{print $2}' <<<"$listed" | LC_ALL=C sort)" = "$verified" ] \
    || die "$1 does not list exactly the .deb files whose provenance was verified (VERIFIED_DEB_SHA256S)"

  [[ "${KEYRING_DEB_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] \
    || die "KEYRING_DEB_SHA256 (the attestation-verified digest of the keyring package) is not set"
  keyring_sums=$(awk -v pkg="$KEYRING_PACKAGE" '$1 == pkg {print $2}' <<<"$listed")
  [ "$(grep -c . <<<"$keyring_sums")" -eq 1 ] || die "$1 does not hold exactly one $KEYRING_PACKAGE package"
  [ "$keyring_sums" = "$KEYRING_DEB_SHA256" ] \
    || die "the $KEYRING_PACKAGE in $1 is not the file whose provenance was verified (KEYRING_DEB_SHA256)"
  check_packages_fields "$1"
}

# check_release_is_rebuilt <Release> <index-dir>: Release is byte for byte
# what write_release writes for the Packages files in <index-dir> and the
# Release's own Date. So it carries no field, line or section of its own: apt
# reads the last of a repeated field and any extra section, and what is
# signed must be what the index implies.
check_release_is_rebuilt() {
  local release=$1 index=$2 date rebuilt=$WORK/rebuilt
  date=$(release_field_epoch "$release" Date)
  rm -rf "$rebuilt"
  mkdir -p "$rebuilt/$INDEX_SUBDIR"
  cp "$index"/Packages* "$rebuilt/$INDEX_SUBDIR/"
  write_release "$rebuilt" "$date"
  cmp -s "$rebuilt/Release" "$release" \
    || die "$release is not the Release that these index files give (nothing but the fields and files written by write_release may be in it)"
}

sign_index() {
  local in=$1 out=$2 date sign_fpr
  local -a gpg_options
  [ -n "${SIGN_KEY:-}" ] || die "SIGN_KEY is not set"
  [ -f "$in/Release" ] && [ -f "$in/Packages" ] || die "$in needs Release and Packages"
  sign_fpr=$(check_online_signer "$KEYRING_FILE" "$SIGN_KEY")
  log "signing key $sign_fpr is the key in $KEYRING_FILE"
  check_release_window "$in/Release" "$((VALID_UNTIL_DAYS - 1))"
  date=$(release_field_epoch "$in/Release" Date)
  [ $(($(now_epoch) - date)) -le "$MAX_RELEASE_AGE_SECONDS" ] || die "$in/Release was written more than a day ago"
  check_index_is_verified "$in/Packages"
  # Packages.gz and .xz are not here: they are Packages, compressed.
  mkdir "$WORK/index"
  cp "$in/Packages" "$WORK/index/"
  write_index_archives "$WORK/index/Packages"
  check_release_is_rebuilt "$in/Release" "$WORK/index"
  mkdir -p "$out"
  cp "$in/Release" "$out/Release"
  online_gpg_options gpg_options
  sign_release "$out" "${gpg_options[@]}"
  verify_release_signatures "$out" "$KEYRING_FILE"
  log "signed Release (valid until $(release_field "$out/Release" Valid-Until)) and checked it against $KEYRING_FILE"
}

install_signatures() {
  local signed=$1 repo=$2 dist index
  dist=$(repo_dist_dir "$repo")
  index=$dist/$INDEX_SUBDIR
  [ -f "$signed/Release" ] && [ -f "$signed/InRelease" ] && [ -f "$signed/Release.gpg" ] \
    || die "$signed needs Release, InRelease and Release.gpg"
  verify_release_signatures "$signed" "$KEYRING_FILE"
  check_release_window "$signed/Release" "$((VALID_UNTIL_DAYS - 1))"
  check_release_is_rebuilt "$signed/Release" "$index"
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
