#!/usr/bin/env bash
# Carry small files between jobs as one base64 line (a job output), so the
# job with the signing key needs no artifact storage and no .deb.
#
# Usage: signing-bundle.sh pack <dir> > bundle.b64
#        signing-bundle.sh unpack <empty-dir> < bundle.b64
#
# The bundle is a gzip tar of regular files named Release, Packages,
# InRelease, Release.gpg or tags/<name>.payload|.sig, nothing else (no links,
# no other path, no more than MAX_FILES files, at most MAX_BYTES unpacked).
# unpack refuses anything else before it writes a file.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

readonly MAX_FILES=40
readonly MAX_BYTES=2000000
readonly NAME_REGEX='^(Release|Packages|InRelease|Release\.gpg|tags/[A-Za-z0-9][A-Za-z0-9._+-]*\.(payload|sig))$'

pack() {
  local dir=$1 name
  local -a names=()
  while IFS= read -r name; do
    [[ "$name" =~ $NAME_REGEX ]] || die "$name may not go in a bundle"
    names+=("$name")
  done < <(cd "$dir" && find . -type f -printf '%P\n' | LC_ALL=C sort)
  [ "${#names[@]}" -gt 0 ] || die "nothing to pack in $dir"
  tar -C "$dir" -czf - "${names[@]}" | base64 -w0
  echo
}

unpack() {
  local dir=$1 bundle line total name
  bundle="$dir.bundle.tgz"
  [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ] || die "$dir must be an empty directory"
  base64 -d > "$bundle" || die "the bundle is not base64"
  [ "$(tar -tzf "$bundle" | wc -l)" -le "$MAX_FILES" ] || die "the bundle holds more than $MAX_FILES files"
  while IFS= read -r line; do
    [ "${line:0:1}" = - ] || die "the bundle holds something that is not a regular file: $line"
  done < <(tar -tvzf "$bundle")
  while IFS= read -r name; do
    [[ "$name" =~ $NAME_REGEX ]] || die "the bundle holds '$name'"
  done < <(tar -tzf "$bundle")
  total=$(tar -xzOf "$bundle" | wc -c)
  [ "$total" -le "$MAX_BYTES" ] || die "the bundle unpacks to more than $MAX_BYTES bytes"
  tar -C "$dir" --no-same-owner --no-same-permissions -xzf "$bundle"
  rm -f "$bundle"
}

case "${1:-} $#" in
  "pack 2") pack "$2" ;;
  "unpack 2") unpack "$2" ;;
  *) die "usage: signing-bundle.sh pack <dir> | unpack <empty-dir>" ;;
esac
