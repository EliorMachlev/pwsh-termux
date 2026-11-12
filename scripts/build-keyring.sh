#!/usr/bin/env bash
# Build the pwsh-termux-keyring .deb: the repository's public keys and the
# apt source that trusts them for this repository only (signed-by), so a user
# sets the repository up by installing one package and removes it with one
# `pkg remove`. The keys come from keys/pwsh-termux-archive-keyring.gpg, which
# is committed to Git: the online signing key, the offline recovery key once
# keys/RECOVERY names it, and the next online key while keys/ROTATION names it
# (check-keys.sh). The build is deterministic (same key file and script, same
# bytes).
#
# New keys reach users through `pkg upgrade`: a planned rotation ships the
# next key while the current one still signs; after a lost or compromised
# online key, the maintainer signs the index that carries the new keyring with
# the recovery key. Only a user who misses those windows, or a compromise with
# no recovery key, needs a manual reinstall. See
# docs/markDown/engineering/release.md.
#
# Usage: build-keyring.sh <outdir>
# Prints the path of the built .deb on stdout (everything else goes to stderr)
# and writes <deb>.build.json next to it for make-sboms.sh.
#
# Env: KEYRING_FILE      TEST ONLY: a different public keyring (for a throwaway
#                        key in local and CI tests). Default and production:
#                        keys/pwsh-termux-archive-keyring.gpg.
#      SOURCE_DATE_EPOCH timestamp for every file in the package. Default: the
#                        creation time of the key, read from the key file, so
#                        the bytes depend on the file's content only (not on
#                        Git history or the time of the build).
#      TERMUX_PREFIX     (default: /data/data/com.termux/files/usr)
set -euo pipefail
umask 022   # deterministic package permissions regardless of the caller's umask
source "$(dirname "$0")/lib/common.sh"

# Bump on every change to the package's content: a key added or dropped, the
# source line, this script's layout or control fields.
readonly KEYRING_VERSION=1.1.0

OUT_DIR=${1:?output directory}
KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}
TERMUX_PREFIX=${TERMUX_PREFIX:-$DEFAULT_TERMUX_PREFIX}

readonly SITE_URL=https://pwsh-termux.machlev.org
readonly PROJECT_GITHUB_URL=https://github.com/EliorMachlev/pwsh-termux
readonly KEYRING_PATH=$TERMUX_PREFIX/$KEYRING_INSTALL_SUBDIR/$KEYRING_BASENAME
readonly SOURCES_LIST_DIR=$TERMUX_PREFIX/etc/apt/sources.list.d
# Same file name as the manual install: two sources for one URI with
# different Signed-By values are an apt error.
readonly SOURCES_LIST_FILE=$SOURCES_LIST_DIR/$PROJECT_NAME.list
readonly SOURCE_LINE="deb [signed-by=$KEYRING_PATH] $SITE_URL $APT_SUITE $APT_COMPONENT"
readonly DOC_DIR=$TERMUX_PREFIX/share/doc/$KEYRING_PACKAGE
readonly MAINTAINER="pwsh-termux packagers <noreply@users.noreply.github.com>"

# Removed on exit.
WORK_DIR=

# The keyring file as the build record names it.
keyring_source_name() {
  if is_production_keyring "$KEYRING_FILE"; then
    printf '%s\n' "keys/$KEYRING_BASENAME"
  else
    printf '%s\n' "$KEYRING_FILE (test keyring)"
  fi
}

# key_creation_time <keyring-file>: the first primary key's creation time
# (seconds since the epoch).
key_creation_time() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null \
    | awk -F: '$1 == "pub" {print $6; exit}'
}

# SOURCE_DATE_EPOCH: as given, or the key's creation time, so the bytes depend
# on the keyring file's content only (not on Git history or the build time).
set_source_date_epoch() {
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH=$(key_creation_time "$KEYRING_FILE")
  fi
  [[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || die "no usable SOURCE_DATE_EPOCH: '$SOURCE_DATE_EPOCH'"
  export SOURCE_DATE_EPOCH
  log "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
}

# stage_files <stage-dir>: the keyring, the apt source and the copyright file.
stage_files() {
  local stage=$1
  mkdir -p "$stage$TERMUX_PREFIX/$KEYRING_INSTALL_SUBDIR" \
           "$stage$SOURCES_LIST_DIR" \
           "$stage$DOC_DIR"
  install -m 644 "$KEYRING_FILE" "$stage$KEYRING_PATH"
  printf '%s\n' "$SOURCE_LINE" > "$stage$SOURCES_LIST_FILE"
  {
    echo "Public keys and apt source of the unofficial pwsh-termux repository"
    echo "($SITE_URL). MIT license: see the project's LICENSE at"
    echo "$PROJECT_GITHUB_URL."
  } > "$stage$DOC_DIR/copyright"
}

# installed_size_kib <stage-dir>: Installed-Size as dpkg-gencontrol counts it
# (KiB per file, rounded up; one per directory), so it does not depend on the
# build machine's file system.
installed_size_kib() {
  find "$1" -mindepth 1 -printf '%y %s\n' \
    | awk '$1 == "f" {kb += int(($2 + 1023) / 1024); next} {kb += 1} END {print kb}'
}

# write_control <stage-dir> <installed-size-kib>
write_control() {
  local stage=$1 installed_kib=$2
  mkdir -p "$stage/DEBIAN"
  cat > "$stage/DEBIAN/control" <<CTRL
Package: $KEYRING_PACKAGE
Version: $KEYRING_VERSION
Architecture: all
Maintainer: $MAINTAINER
Installed-Size: $installed_kib
Section: misc
Priority: optional
Homepage: $SITE_URL/
Description: Signing keys and apt source for the pwsh-termux repository
 Installs the public keys of the pwsh-termux apt repository and a source
 line that trusts them for this repository only (signed-by).
 New keys arrive with pkg upgrade (planned rotation, and recovery with
 the offline key once it is set up). Removing it removes both files.
CTRL
}

# build_deb <stage-dir> <deb>: every timestamp is SOURCE_DATE_EPOCH, and xz
# runs single-threaded (its multi-threaded output depends on the number of
# CPUs).
build_deb() {
  local stage=$1 deb=$2
  find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  mkdir -p "$OUT_DIR"
  dpkg-deb --root-owner-group --threads-max=1 -Zxz -z9 --build "$stage" "$deb" >&2
  log "built $deb"
}

# write_build_record <deb>: <deb-without-.deb>.build.json, for the SBOMs
# (make-sboms.sh); not part of the package.
write_build_record() {
  local deb=$1
  python3 - "${deb%.deb}.build.json" "$KEYRING_PACKAGE" "$KEYRING_VERSION" \
    "$(keyring_source_name)" "$(sha256_of "$KEYRING_FILE")" "$SOURCE_DATE_EPOCH" <<'PY'
import json, sys
out, pkg, ver, src, sha, epoch = sys.argv[1:7]
json.dump({"package": pkg, "version": ver, "architecture": "all",
           "source_file": src,
           "source_sha256": sha, "source_date_epoch": int(epoch)},
          open(out, "w"), indent=2)
PY
}

main() {
  local stage installed_kib deb
  check_keyring "$KEYRING_FILE" >&2 || die "$KEYRING_FILE failed the key check"
  set_source_date_epoch

  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  stage="$WORK_DIR/stage"
  stage_files "$stage"
  installed_kib=$(installed_size_kib "$stage")
  write_control "$stage" "$installed_kib"

  deb="$OUT_DIR/${KEYRING_PACKAGE}_${KEYRING_VERSION}_all.deb"
  build_deb "$stage" "$deb"
  write_build_record "$deb"
  printf '%s\n' "$deb"
}

main
