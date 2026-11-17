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
# GitHub limits the job outputs of a job to 1 MB.
readonly MAX_ENCODED_CHARS=900000
readonly NAME_REGEX='^(Release|Packages|InRelease|Release\.gpg|tags/[A-Za-z0-9][A-Za-z0-9._+-]*\.(payload|sig))$'

pack() {
  local dir=$1 name encoded
  local -a names=()
  while IFS= read -r name; do
    [[ "$name" =~ $NAME_REGEX ]] || die "$name may not go in a bundle"
    names+=("$name")
  done < <(cd "$dir" && find . -type f -printf '%P\n' | LC_ALL=C sort)
  [ "${#names[@]}" -gt 0 ] || die "nothing to pack in $dir"
  encoded=$(tar -C "$dir" -czf - "${names[@]}" | base64 -w0)
  [ "${#encoded}" -le "$MAX_ENCODED_CHARS" ] || die "the bundle is ${#encoded} characters: more than a job output may carry ($MAX_ENCODED_CHARS)"
  printf '%s\n' "$encoded"
}

unpack() {
  local dir=$1 bundle=$1.bundle.tgz listing=$1.bundle.list line name count total
  [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ] || die "$dir must be an empty directory"
  base64 -d > "$bundle" || die "the bundle is not base64"
  tar -tvzf "$bundle" > "$listing" || die "the bundle is not a gzip tar"
  count=$(wc -l < "$listing")
  [ "$count" -gt 0 ] || die "the bundle holds no file"
  [ "$count" -le "$MAX_FILES" ] || die "the bundle holds more than $MAX_FILES files"
  while IFS= read -r line; do
    [ "${line:0:1}" = - ] || die "the bundle holds something that is not a regular file: $line"
  done < "$listing"
  tar -tzf "$bundle" > "$listing" || die "the bundle is not a gzip tar"
  while IFS= read -r name; do
    [[ "$name" =~ $NAME_REGEX ]] || die "the bundle holds '$name'"
  done < "$listing"
  total=$(tar -xzOf "$bundle" | wc -c)
  [ "$total" -le "$MAX_BYTES" ] || die "the bundle unpacks to more than $MAX_BYTES bytes"
  tar -C "$dir" --no-same-owner --no-same-permissions -xzf "$bundle"
  rm -f "$bundle" "$listing"
}

case "${1:-} $#" in
  "pack 2") pack "$2" ;;
  "unpack 2") unpack "$2" ;;
  *) die "usage: signing-bundle.sh pack <dir> | unpack <empty-dir>" ;;
esac
