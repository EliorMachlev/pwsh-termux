#!/usr/bin/env bash
# Signed release tags. Each pwsh and pwsh-preview release on GitHub sits on
# an annotated tag that update.yaml's sign job signs with the online
# signing key (the key in keys/ that signs the apt index), on the commit that
# built the package. The release is then made on that tag with
# `gh release create --verify-tag`, so gh never creates a lightweight one.
#
# Usage: release-tags.sh name <deb>
#        release-tags.sh sign <debs-dir> <commit>
#        release-tags.sh verify <tag>
#        release-tags.sh push <tag> <remote>
#        release-tags.sh payloads <debs-dir> <commit> <out-dir>
#        release-tags.sh sign-payloads <in-dir> <commit> <out-dir>
#        release-tags.sh assemble <dir>
# Env:   SIGN_KEY      (sign) the online key's id or fingerprint
#        GPG_PASSPHRASE_FILE  (sign) its passphrase file, as for build-repo.sh
#        GH_TOKEN      (push) the job's GITHUB_TOKEN (contents: write); git
#                      gets it from `gh auth git-credential`, so it is never
#                      in an argument, a file or .git/config
#        KEYRING_FILE  TEST ONLY: the keyring to verify against instead of
#                      keys/pwsh-termux-archive-keyring.gpg
#
#   name    the release tag of a pwsh or pwsh-preview .deb:
#           <package>-<version>, '~' written as '-' (a git tag cannot hold
#           '~'): pwsh-7.7.0-1, pwsh-preview-7.8.0-preview.1-1
#   sign    for each pwsh or pwsh-preview .deb in the folder whose tag this
#           clone does not have yet (update.yaml's checkout has every tag),
#           writes the tag object with git mktag, signed as `git tag -s`
#           signs (an armored detached signature by SIGN_KEY appended to the
#           payload), tagger github-actions[bot]; checks it as verify does;
#           only then creates refs/tags/<tag>. An existing tag is left alone
#           (the Tag Protection ruleset forbids moving one).
#   payloads, sign-payloads, assemble
#           `sign` in three steps, so the key can live in a job that never
#           sees a .deb: payloads (no key) writes <tag>.payload for each
#           package that has no tag yet; sign-payloads (the key; <commit>
#           is the run's commit) checks that each payload is exactly what
#           `payloads` writes for that commit and signs it as <tag>.sig;
#           assemble (no key) turns each payload and signature into the tag
#           object, verifies it as verify does and creates refs/tags/<tag>.
#   verify  the tag is an annotated tag whose object names <tag>, points at
#           a commit, and carries exactly one OpenPGP signature, which
#           verifies with gpgv against the keyring file alone and was made by
#           one of its online keys (the current one or, during a planned
#           rotation, the next one; never the recovery key). Prints the
#           signer's fingerprint.
#   push    verify, then push the tag unless the remote has it; if it does,
#           it must be the same tag object. Exits 3 (EXIT_DEFERRED) and
#           pushes nothing when the tagged commit's .github/workflows differs
#           from the remote main's: GitHub refuses a new ref that a
#           GITHUB_TOKEN creates on such a commit (the token can never hold
#           the workflows permission). That happens only when main moved
#           during the run; the next run tags its own commit.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KEYRING_FILE=${KEYRING_FILE:-$DEFAULT_KEYRING_FILE}
readonly EXIT_DEFERRED=3
readonly SIGNATURE_BEGIN='-----BEGIN PGP SIGNATURE-----'
readonly WORKFLOWS_PATH=.github/workflows
readonly TAG_MESSAGE="Built from this commit by update.yaml and signed with the repository's online signing key. Verify it with git tag -v and that key: keys/$KEYRING_BASENAME, or https://pwsh-termux.machlev.org/$PUBLISHED_KEY_ASC; the fingerprints are in SECURITY.md."

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# is_released_package <deb>: true for the packages that get a GitHub release.
is_released_package() {
  case $(dpkg-deb -f "$1" Package) in
    pwsh | pwsh-preview) return 0 ;;
    *) return 1 ;;
  esac
}

# release_tag_name <deb>: as `name` above.
release_tag_name() {
  local deb=$1 name version tag
  is_released_package "$deb" || die "$deb is not a pwsh or pwsh-preview package"
  name=$(dpkg-deb -f "$deb" Package)
  version=$(dpkg-deb -f "$deb" Version)
  tag="$name-${version//\~/-}"
  git check-ref-format "refs/tags/$tag" || die "$deb: '$tag' is not a valid tag name"
  printf '%s\n' "$tag"
}

# tag_header <file> <field>: a header field of a tag object (before the
# first empty line), or nothing.
tag_header() {
  awk -v name="$2" 'NF == 0 {exit} $1 == name {print substr($0, length(name) + 2); exit}' "$1"
}

# verify_tag_object <object> <tag>: as `verify` above, for a tag object (a
# ref or an id). Prints the signer's fingerprint.
verify_tag_object() {
  local object=$1 tag=$2 body=$W/verify-body count line fingerprint online
  [ "$(git cat-file -t "$object" 2>/dev/null)" = tag ] \
    || die "$tag is not an annotated tag (a lightweight tag carries no signature)"
  git cat-file tag "$object" > "$body"
  [ "$(tag_header "$body" tag)" = "$tag" ] \
    || die "the tag object of $tag is named '$(tag_header "$body" tag)'"
  [ "$(tag_header "$body" type)" = commit ] || die "$tag does not point at a commit"
  count=$(grep -cxF -- "$SIGNATURE_BEGIN" "$body" || true)
  [ "$count" -eq 1 ] || die "$tag carries $count OpenPGP signatures, not 1"
  # What git verifies: the payload is every byte before the signature.
  line=$(grep -nxF -- "$SIGNATURE_BEGIN" "$body" | cut -d: -f1)
  head -n "$((line - 1))" "$body" > "$W/verify-payload"
  tail -n "+$line" "$body" > "$W/verify-signature"
  gpgv --status-fd 1 --keyring "$(realpath "$KEYRING_FILE")" \
    "$W/verify-signature" "$W/verify-payload" > "$W/verify-status" 2>/dev/null \
    || die "the signature of $tag does not verify against $KEYRING_FILE"
  # VALIDSIG's last field is the primary key's fingerprint.
  fingerprint=$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" {print $NF}' "$W/verify-status")
  online=$(check_keyring "$KEYRING_FILE" | online_fingerprints)
  if [ -z "$fingerprint" ] || ! grep -qxF -- "$fingerprint" <<<"$online"; then
    die "$tag is signed by ${fingerprint:-no key}, not by an online key of $KEYRING_FILE"
  fi
  printf '%s\n' "$fingerprint"
}

# write_tag_payload <commit> <tag> <title> <epoch> <file>: the tag object
# without its signature.
write_tag_payload() {
  {
    printf 'object %s\ntype commit\ntag %s\n' "$1" "$2"
    printf 'tagger %s %s +0000\n\n' "$GITHUB_ACTIONS_BOT_IDENTITY" "$4"
    printf '%s\n\n%s\n' "$3" "$TAG_MESSAGE"
  } > "$5"
}

# sign_payload <payload> <signature>: an armored detached signature by SIGN_KEY.
sign_payload() {
  local payload=$1 signature=$2
  local -a gpg_options
  online_gpg_options gpg_options
  rm -f "$signature"
  gpg "${gpg_options[@]}" --armor --detach-sign -o "$signature" "$payload" \
    || die "gpg could not sign $payload: is the key passphrase-protected, and is GPG_PASSPHRASE_FILE set to its passphrase?"
}

# attach_signature <payload> <signature> <tag> <commit>: the tag object from
# a payload and its signature, verified, as refs/tags/<tag>.
attach_signature() {
  local payload=$1 signature=$2 tag=$3 commit=$4 object fingerprint
  object=$(cat "$payload" "$signature" | git mktag) || die "git mktag refused the tag object of $tag"
  fingerprint=$(verify_tag_object "$object" "$tag")
  # "" as the old value: fails if the tag appeared meanwhile.
  git update-ref "refs/tags/$tag" "$object" "" || die "could not create refs/tags/$tag"
  log "signed $tag on $commit with $fingerprint"
}

# sign_tag <commit> <tag> <title>: create refs/tags/<tag>, signed, on the commit.
sign_tag() {
  write_tag_payload "$1" "$2" "$3" "$(now_epoch)" "$W/sign-payload"
  sign_payload "$W/sign-payload" "$W/sign-signature"
  attach_signature "$W/sign-payload" "$W/sign-signature" "$2" "$1"
}

# For each released package in the folder whose tag this clone lacks:
# "<tag><TAB><title>" lines.
unreleased_tags() {
  local deb tag
  shopt -s nullglob
  for deb in "$1"/*.deb; do
    is_released_package "$deb" || continue
    tag=$(release_tag_name "$deb")
    if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
      log "$tag exists already; left as it is"
      continue
    fi
    printf '%s\t%s %s\n' "$tag" "$(dpkg-deb -f "$deb" Package)" "$(dpkg-deb -f "$deb" Version)"
  done
}

# A tag name that is also a safe file name.
readonly PAYLOAD_TAG_REGEX='^pwsh(-preview)?-[A-Za-z0-9][A-Za-z0-9._+-]*$'

write_payloads() {
  local debs_dir=$1 commit tag title out=$3
  commit=$(git rev-parse --verify --quiet --end-of-options "$2^{commit}") || die "$2 is not a commit here"
  mkdir -p "$out"
  while IFS=$'\t' read -r tag title; do
    [[ "$tag" =~ $PAYLOAD_TAG_REGEX ]] || die "'$tag' is not a tag name a payload may carry"
    write_tag_payload "$commit" "$tag" "$title" "$(now_epoch)" "$out/$tag.payload"
    log "payload for $tag on $commit"
  done < <(unreleased_tags "$debs_dir")
}

# sign_payloads <in-dir> <commit> <out-dir>: only a payload that is exactly
# what write_payloads writes for <commit> (with its own title and time) is signed.
sign_payloads() {
  local in=$1 commit=$2 out=$3 payload tag title epoch now signed=0
  [ -n "${SIGN_KEY:-}" ] || die "SIGN_KEY is not set"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "$commit is not a commit id"
  mkdir -p "$out"
  shopt -s nullglob
  for payload in "$in"/*.payload; do
    tag=$(basename "$payload" .payload)
    [[ "$tag" =~ $PAYLOAD_TAG_REGEX ]] || die "'$tag' is not a tag name a payload may carry"
    title=$(sed -n '6p' "$payload")
    [[ "$title" =~ ^pwsh(-preview)?\ [A-Za-z0-9][A-Za-z0-9.+~:-]*$ ]] || die "$payload: unexpected title '$title'"
    epoch=$(sed -n '4p' "$payload" | awk '{print $(NF - 1)}')
    [[ "$epoch" =~ ^[0-9]{9,11}$ ]] || die "$payload: unexpected tagger time '$epoch'"
    now=$(now_epoch)
    { [ $((now - epoch)) -le "$SECONDS_PER_DAY" ] && [ "$epoch" -le $((now + RELEASE_CLOCK_SKEW_SECONDS)) ]; } \
      || die "$payload: the tagger time is not within the last day"
    write_tag_payload "$commit" "$tag" "$title" "$epoch" "$W/expected-payload"
    cmp -s "$W/expected-payload" "$payload" || die "$payload is not the tag payload of $tag on $commit"
    [ "${title%% *}" = "${tag%%-[0-9]*}" ] || die "$payload: the title '$title' does not match the tag $tag"
    sign_payload "$payload" "$out/$tag.sig"
    cp "$payload" "$out/$tag.payload"
    signed=$((signed + 1))
  done
  log "signed $signed tag payload(s) for $commit"
}

assemble_tags() {
  local dir=$1 payload tag commit
  shopt -s nullglob
  for payload in "$dir"/*.payload; do
    tag=$(basename "$payload" .payload)
    [[ "$tag" =~ $PAYLOAD_TAG_REGEX ]] || die "'$tag' is not a tag name a payload may carry"
    [ -f "$dir/$tag.sig" ] || die "$tag has a payload but no signature"
    if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
      log "$tag exists already; left as it is"
      continue
    fi
    commit=$(sed -n '1s/^object //p' "$payload")
    attach_signature "$payload" "$dir/$tag.sig" "$tag" "$commit"
  done
}

sign_tags() {
  local debs_dir=$1 commit tag title
  [ -n "${SIGN_KEY:-}" ] || die "SIGN_KEY is not set"
  commit=$(git rev-parse --verify --quiet --end-of-options "$2^{commit}") || die "$2 is not a commit here"
  while IFS=$'\t' read -r tag title; do
    sign_tag "$commit" "$tag" "$title"
  done < <(unreleased_tags "$debs_dir")
}

# git_auth <git-argument...>: git with gh as the credential helper for https
# remotes (gh reads GH_TOKEN from the environment). A file:// remote needs none.
git_auth() {
  git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

push_tag() {
  local tag=$1 remote=$2 ref="refs/tags/$1" local_object remote_refs remote_object commit
  verify_tag_object "$ref" "$tag" >/dev/null
  local_object=$(git rev-parse --verify "$ref")
  remote_refs=$(git_auth ls-remote "$remote" "$ref") || die "could not read the tags of $remote"
  remote_object=$(awk -v ref="$ref" '$2 == ref {print $1}' <<<"$remote_refs")
  if [ -n "$remote_object" ]; then
    [ "$remote_object" = "$local_object" ] \
      || die "$remote has another $tag ($remote_object, not $local_object)"
    log "$remote has $tag already"
    return 0
  fi
  commit=$(git rev-parse --verify "$ref^{commit}")
  git_auth fetch --quiet --no-tags "$remote" refs/heads/main || die "could not fetch main from $remote"
  if [ "$(git rev-parse --verify --quiet "$commit:$WORKFLOWS_PATH" || true)" \
       != "$(git rev-parse --verify --quiet "FETCH_HEAD:$WORKFLOWS_PATH" || true)" ]; then
    log "WARNING: $WORKFLOWS_PATH on $remote's main differs from $commit's, so GitHub would refuse $tag from a GITHUB_TOKEN; not pushed (the next run tags its own commit)"
    return "$EXIT_DEFERRED"
  fi
  git_auth push --quiet "$remote" "$ref:$ref" || die "could not push $tag to $remote"
  log "pushed $tag to $remote"
}

case "${1:-} $#" in
  "name 2") release_tag_name "$2" ;;
  "sign 3") sign_tags "$2" "$3" ;;
  "verify 2") verify_tag_object "refs/tags/$2" "$2" ;;
  "push 3") push_tag "$2" "$3" ;;
  "payloads 4") write_payloads "$2" "$3" "$4" ;;
  "sign-payloads 4") sign_payloads "$2" "$3" "$4" ;;
  "assemble 2") assemble_tags "$2" ;;
  *) die "usage: release-tags.sh name <deb> | sign <debs-dir> <commit> | verify <tag> | push <tag> <remote> | payloads <debs-dir> <commit> <out-dir> | sign-payloads <in-dir> <commit> <out-dir> | assemble <dir>" ;;
esac
