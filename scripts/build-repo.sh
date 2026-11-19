#!/usr/bin/env bash
# Assemble an UNSIGNED apt repository from .deb files. Signing is a separate
# step (sign-release.sh sign, in a job that never sees a .deb; then
# sign-release.sh install, which checks the signed Release against this
# repository's index files).
#
# Usage: build-repo.sh <debs-dir> <repo-dir>
# Env:   KEYRING_FILE  TEST ONLY: the public keyring to check against and
#                   publish instead of keys/pwsh-termux-archive-keyring.gpg
#                   (for a throwaway key; see docs/markDown/engineering/build.md).
#
# It fails closed unless the keyring file (keys/) passes check-keys.sh, and the
# keyring package in the debs folder (if any) ships exactly that file, byte
# for byte. The package is published as it is.
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
#   repo/dists/stable/Release   (InRelease and Release.gpg come from sign-release.sh)
#   repo/dists/stable/main/binary-aarch64/Packages{,.gz,.xz}
#   repo/pwsh-termux.gpg  pwsh-termux.asc   (the keyring file, binary and armored)
#   repo/pwsh-termux-keyring.deb            (the keyring package under a fixed name)
# The website is merged in afterwards by assemble-site.sh.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

DEBS_DIR=${1:?debs directory}
REPO_DIR=${2:?repo output directory}
KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}

DIST_DIR=$(repo_dist_dir "$REPO_DIR")
INDEX_DIR=$DIST_DIR/$(repo_index_subdir)
RELEASE_FILE=$DIST_DIR/Release
readonly DIST_DIR INDEX_DIR RELEASE_FILE

# Set by find_debs: every .deb, and the keyring package among them (0 or 1).
debs=()
keyring_debs=()

find_debs() {
  shopt -s nullglob
  debs=("$DEBS_DIR"/*.deb)
  [ "${#debs[@]}" -gt 0 ] || die "no .deb files in $DEBS_DIR"
  keyring_debs=("$DEBS_DIR"/"$KEYRING_PACKAGE"_*.deb)
  [ "${#keyring_debs[@]}" -le 1 ] || die "more than one $KEYRING_PACKAGE package in $DEBS_DIR"
}

# The keyring package, when present, must ship exactly the keyring file.
check_keyring_package_contents() {
  if [ "${#keyring_debs[@]}" -eq 1 ]; then
    deb_ships_keyring "${keyring_debs[0]}" "$KEYRING_FILE" \
      || die "${keyring_debs[0]} does not ship $KEYRING_FILE"
  fi
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
  write_index_archives "$INDEX_DIR/Packages"
}

write_signable_release() {
  write_release "$DIST_DIR" "$(now_epoch)"
  check_release_window "$RELEASE_FILE" "$((VALID_UNTIL_DAYS - 1))"
  log "Release valid until $(release_field "$RELEASE_FILE" Valid-Until)"
}

main() {
  find_debs
  check_keyring "" >/dev/null
  check_keyring_package_contents

  rm -rf "$REPO_DIR"
  mkdir -p "$REPO_DIR"
  write_key_files
  write_pool_and_packages
  write_signable_release

  log "repository is UNSIGNED (sign-release.sh signs it)"

  touch "$REPO_DIR/.nojekyll"
  log "repository written to $REPO_DIR"
}

main
