#!/usr/bin/env bash
# Assemble a signed apt repository from .deb files.
#
# Usage: build-repo.sh <debs-dir> <repo-dir>
# Env:   SIGN_KEY   gpg key id/fingerprint to sign with. If unset the repo is
#                   left UNSIGNED (fine for local tests, not for publishing).
#        GPG_PASSPHRASE_FILE  the signing key's passphrase file (first line);
#                   required for a passphrase-protected key, which otherwise
#                   fails to sign (gpg never prompts here)
#        KEYRING_FILE  TEST ONLY: the public keyring to check against and
#                   publish instead of keys/pwsh-termux-archive-keyring.gpg
#                   (for a throwaway key; see docs/markDown/engineering/build.md).
#
#        KEYRING_DEB_SHA256  the SHA-256 of the pwsh-termux-keyring .deb in the
#                   debs folder, as its build provenance was verified by the
#                   caller (update.yaml: scripts/verify-attestation.sh, in a
#                   job without the signing key). Required when signing.
#
# When signing, it fails closed unless all of these hold:
#   - the keyring file (keys/) passes check-keys.sh, and the signing key is
#     its current online key, or, while keys/ROTATION marks a planned
#     rotation, the next one; a secret replaced without keys/, or the
#     reverse, stops here;
#   - the signing key is not the recovery key (keys/RECOVERY), and no secret
#     for the recovery key is in this gpg home at all (it never belongs in CI);
#   - the debs folder holds one pwsh-termux-keyring package, and its SHA-256
#     is KEYRING_DEB_SHA256 (the file whose attestation was verified);
#   - that package ships exactly the keyring file, byte for byte;
#   - the signed index verifies against the keyring file with gpgv, as apt will.
# The package from the debs folder is published as it is.
#
# Release carries Date and Valid-Until = Date + VALID_UNTIL_DAYS (14) days
# (scripts/lib/common.sh): apt refuses the index after that, so an old index
# cannot be replayed to users for longer (a freeze attack). update.yaml runs
# daily and re-signs it, which moves the window on. Only Release, InRelease
# and Release.gpg depend on the time: the same .deb files give byte-identical
# Packages, Packages.gz and Packages.xz, so a daily re-sign makes clients
# fetch only the small InRelease, and never offers an upgrade.
#
# Layout (suite "stable", component "main", arch "aarch64"):
#   repo/pool/main/<pkg>/*.deb
#   repo/dists/stable/{Release,InRelease,Release.gpg}
#   repo/dists/stable/main/binary-aarch64/Packages{,.gz,.xz}
#   repo/pwsh-termux.gpg  pwsh-termux.asc   (the keyring file, binary and armored)
#   repo/pwsh-termux-keyring.deb            (the keyring package under a fixed name)
# The website is merged in afterwards by assemble-site.sh.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

DEBS_DIR=${1:?debs directory}
REPO_DIR=${2:?repo output directory}
KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}

readonly RELEASE_ORIGIN=$PROJECT_NAME
readonly RELEASE_DESCRIPTION="Unofficial PowerShell packages for Termux (glibc)"
DIST_DIR=$(repo_dist_dir "$REPO_DIR")
INDEX_DIR=$DIST_DIR/$(repo_index_subdir)
RELEASE_FILE=$DIST_DIR/Release
readonly DIST_DIR INDEX_DIR RELEASE_FILE

# Set by find_debs: every .deb, and the keyring package among them (0 or 1).
debs=()
keyring_debs=()
# Set by read_key_roles: the keys that may sign, and the recovery key.
online_fprs=
recovery_fpr=
# Set by check_signer: the signing key's fingerprint.
sign_fpr=

find_debs() {
  shopt -s nullglob
  debs=("$DEBS_DIR"/*.deb)
  [ "${#debs[@]}" -gt 0 ] || die "no .deb files in $DEBS_DIR"
  keyring_debs=("$DEBS_DIR"/"$KEYRING_PACKAGE"_*.deb)
  [ "${#keyring_debs[@]}" -le 1 ] || die "more than one $KEYRING_PACKAGE package in $DEBS_DIR"
}

# The keyring file's keys and their roles (current, next, recovery).
read_key_roles() {
  local key_roles
  key_roles=$(check_keyring "$KEYRING_FILE")
  online_fprs=$(online_fingerprints <<<"$key_roles")
  recovery_fpr=$(fingerprints_with_role "$ROLE_RECOVERY" <<<"$key_roles")
}

# The keyring package, when present, must ship exactly the keyring file.
check_keyring_package_contents() {
  if [ "${#keyring_debs[@]}" -eq 1 ]; then
    deb_ships_keyring "${keyring_debs[0]}" "$KEYRING_FILE" \
      || die "${keyring_debs[0]} does not ship $KEYRING_FILE"
  fi
}

# The signing key is the online key (never the recovery key, whose secret
# must not even be in this gpg home).
check_signer() {
  sign_fpr=$(secret_key_fingerprint "$SIGN_KEY")
  [ -n "$sign_fpr" ] || die "no secret key for SIGN_KEY in the keyring"
  [ "$sign_fpr" != "$recovery_fpr" ] \
    || die "refusing to sign with the recovery key $recovery_fpr: it is offline only (scripts/recovery-sign.sh)"
  if [ -n "$recovery_fpr" ] && gpg --batch --list-secret-keys -- "$recovery_fpr" >/dev/null 2>&1; then
    die "the secret of the recovery key $recovery_fpr is in this gpg home; it must never be where the online key is"
  fi
  grep -qx -- "$sign_fpr" <<<"$online_fprs" \
    || die "the signing key $sign_fpr is not the online key in $KEYRING_FILE ($(tr '\n' ' ' <<<"$online_fprs")); see release.md, rotating the signing key"
}

# The keyring package is the file whose attestation the caller verified.
check_keyring_package_is_verified() {
  [ -n "${KEYRING_DEB_SHA256:-}" ] \
    || die "signing, but KEYRING_DEB_SHA256 (the attestation-verified digest of the keyring package) is not set"
  [ "$(sha256_of "${keyring_debs[0]}")" = "$KEYRING_DEB_SHA256" ] \
    || die "${keyring_debs[0]} is not the file whose provenance was verified (KEYRING_DEB_SHA256)"
}

check_before_signing() {
  [ "${#keyring_debs[@]}" -eq 1 ] || die "signing, but $DEBS_DIR has no $KEYRING_PACKAGE package (build-keyring.sh)"
  check_signer
  check_keyring_package_is_verified
  log "keyring package is the verified file; signing key $sign_fpr is the key in $KEYRING_FILE"
}

# The published key files are the keyring file itself, so the manual install
# and the package trust the same keys.
write_key_files() {
  local key_file armored_key_file
  key_file=$(repo_key_file "$REPO_DIR")
  armored_key_file=$(repo_armored_key_file "$REPO_DIR")
  cp "$KEYRING_FILE" "$key_file"
  gpg --batch --no-default-keyring --import-options import-export --armor \
    --import "$KEYRING_FILE" > "$armored_key_file" 2>/dev/null
  gpg --batch --dearmor < "$armored_key_file" | cmp -s - "$key_file" \
    || die "$PUBLISHED_KEY_ASC is not the armored $PUBLISHED_KEY_GPG"
  if [ "${#keyring_debs[@]}" -eq 1 ]; then
    cp "${keyring_debs[0]}" "$(repo_keyring_deb "$REPO_DIR")"   # a fixed name for the install line
  fi
}

# packages_entry <deb> <pool-path>: the deb's control fields and where and
# what the file is.
packages_entry() {
  local deb=$1 pool_path=$2
  dpkg-deb -f "$deb"
  echo "Filename: $pool_path"
  echo "Size: $(file_size "$deb")"
  echo "MD5sum: $(md5sum "$deb" | cut -d' ' -f1)"
  echo "SHA256: $(sha256_of "$deb")"
  echo
}

# Each .deb into pool/, and the Packages index (plain, .gz and, with xz, .xz).
write_pool_and_packages() {
  local deb package pool_subdir
  mkdir -p "$INDEX_DIR"
  : > "$INDEX_DIR/Packages"
  for deb in "${debs[@]}"; do
    package=$(dpkg-deb -f "$deb" Package)
    pool_subdir=$(repo_pool_subdir "$package")
    mkdir -p "$REPO_DIR/$pool_subdir"
    cp "$deb" "$REPO_DIR/$pool_subdir/"
    packages_entry "$deb" "$pool_subdir/$(basename "$deb")" >> "$INDEX_DIR/Packages"
  done
  gzip -9kn "$INDEX_DIR/Packages"
  if command -v xz >/dev/null; then
    xz -9ke "$INDEX_DIR/Packages"
  fi
}

write_release() {
  local index_file now
  now=$(now_epoch)
  {
    echo "Origin: $RELEASE_ORIGIN"
    echo "Label: $RELEASE_ORIGIN"
    echo "Suite: $APT_SUITE"
    echo "Codename: $APT_SUITE"
    echo "Architectures: $APT_ARCH"
    echo "Components: $APT_COMPONENT"
    echo "Date: $(release_date "$now")"
    echo "Valid-Until: $(release_date $((now + VALID_UNTIL_DAYS * SECONDS_PER_DAY)))"
    echo "Description: $RELEASE_DESCRIPTION"
    echo "SHA256:"
    for index_file in "$INDEX_DIR"/Packages*; do
      echo " $(sha256_of "$index_file") $(file_size "$index_file") ${index_file#"$DIST_DIR/"}"
    done
  } > "$RELEASE_FILE"
  check_release_window "$RELEASE_FILE" "$((VALID_UNTIL_DAYS - 1))"
  log "Release valid until $(release_field "$RELEASE_FILE" Valid-Until)"
}

# --batch with --pinentry-mode loopback: gpg never prompts. A protected key
# signs only with GPG_PASSPHRASE_FILE (update.yaml writes it from the
# GPG_PASSPHRASE secret); without it sign_release dies. The passphrase is only
# ever read from that file, never passed as an argument.
sign_and_verify_release() {
  local -a gpg_options=(--batch --yes --pinentry-mode loopback --local-user "$SIGN_KEY")
  if [ -n "${GPG_PASSPHRASE_FILE:-}" ]; then
    [ -f "$GPG_PASSPHRASE_FILE" ] && [ -r "$GPG_PASSPHRASE_FILE" ] && [ -s "$GPG_PASSPHRASE_FILE" ] \
      || die "GPG_PASSPHRASE_FILE is set but is not a readable, non-empty file"
    gpg_options+=(--passphrase-file "$GPG_PASSPHRASE_FILE")
  fi
  sign_release "$DIST_DIR" "${gpg_options[@]}"
  # What apt will do with the published key: verify both signatures with gpgv
  # against the keyring file alone.
  gpgv_quiet "$(realpath "$KEYRING_FILE")" "$DIST_DIR/InRelease" \
    || die "InRelease does not verify against $KEYRING_FILE"
  gpgv_quiet "$(realpath "$KEYRING_FILE")" "$DIST_DIR/Release.gpg" "$RELEASE_FILE" \
    || die "Release.gpg does not verify against $KEYRING_FILE"
  log "signed with $sign_fpr and verified against $KEYRING_FILE"
}

main() {
  find_debs
  read_key_roles
  check_keyring_package_contents
  if [ -n "${SIGN_KEY:-}" ]; then
    check_before_signing
  fi

  rm -rf "$REPO_DIR"
  mkdir -p "$REPO_DIR"
  write_key_files
  write_pool_and_packages
  write_release

  if [ -n "${SIGN_KEY:-}" ]; then
    sign_and_verify_release
  else
    log "WARNING: SIGN_KEY not set, repository is UNSIGNED"
  fi

  touch "$REPO_DIR/.nojekyll"
  log "repository written to $REPO_DIR"
}

main
