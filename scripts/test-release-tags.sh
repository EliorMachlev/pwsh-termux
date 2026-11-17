#!/usr/bin/env bash
# Tests of release-tags.sh, offline: throwaway Ed25519 keys, stand-in .deb
# files, a local git repository with a bare "remote" reached by file://, no
# network and no real key. Uses the test-only KEYRING_FILE.
#
#   name    the tag of a pwsh and a pwsh-preview package ('~' as '-'); the
#           keyring package refused
#   sign    (payloads, then sign-payloads, then assemble: the three steps of
#           update.yaml) an annotated tag per package, on the given commit, tagger
#           github-actions[bot], verified by gpgv and by `git tag -v` (the
#           user's check), none for the keyring package; an existing tag
#           left as it is; the next key during a rotation accepted; a
#           passphrase-protected key with GPG_PASSPHRASE_FILE accepted and
#           without it, or with an empty file, refused; a stray key, the
#           recovery key, no SIGN_KEY or no commit refused, leaving no tag
#   verify  refuses a lightweight tag, an unsigned annotated tag, a tag
#           object named otherwise, an altered message, two signatures, a
#           signature by the recovery key or by a stray key, a tag of a tree
#   push    pushes a verified tag, then does nothing; refuses an unsigned
#           tag and a remote tag of the same name that is another object;
#           exits 3 and pushes nothing when the remote main's workflows
#           differ from the tagged commit's, pushes when main moved without
#           a workflow change
#
# Usage: test-release-tags.sh
set -euo pipefail
umask 022
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
RT=$SCRIPTS_DIR/release-tags.sh
unset KEYRING_FILE SIGN_KEY GPG_PASSPHRASE_FILE GH_TOKEN GIT_DIR GIT_WORK_TREE
ONLINE=$T/online OFFLINE=$T/offline USER_HOME=$T/user
mkdir -m 700 "$ONLINE" "$OFFLINE" "$USER_HOME"
export GNUPGHOME=$ONLINE

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect_status <exit-status> <description> <command...>
expect_status() {
  local want=$1 what=$2; shift 2
  local got=0
  "$@" >"$T/out.log" 2>"$T/err.log" || got=$?
  if [ "$got" -eq "$want" ]; then
    pass "$what"
    # the reason, so a refusal for the wrong reason is visible
    if [ "$got" -ne 0 ]; then printf '        %s\n' "$(grep -E 'ERROR|WARNING' "$T/err.log" | tail -1)"; fi
  else
    fail "$what (exit $got, expected $want)"
    cat "$T/out.log" "$T/err.log"
  fi
}
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  if [ "$want" = accept ]; then expect_status 0 "$what" "$@"; else expect_status "$EXIT_FAILURE" "$what" "$@"; fi
}
# check <description> <command...>: passes if the command succeeds.
check() {
  local what=$1; shift
  if "$@"; then pass "$what"; else fail "$what"; fi
}
not() { ! "$@"; }
same() { [ "$1" = "$2" ]; }

# newkey <home> <name> [passphrase]: generate a key there and print its fingerprint.
newkey() {
  GNUPGHOME=$1 gpg --batch --pinentry-mode loopback --passphrase "${3:-}" \
    --quick-generate-key "$2 <$2@example.invalid>" ed25519 sign never 2>/dev/null
  GNUPGHOME=$1 gpg --batch --list-secret-keys --with-colons "$2@example.invalid" 2>/dev/null \
    | awk -F: '$1 == "fpr" {print $10; exit}'
}
A=$(newkey "$ONLINE" a)                # the current online key
B=$(newkey "$ONLINE" b)                # the next online key, during a rotation
C=$(newkey "$ONLINE" c)                # a stray key
P=$(newkey "$ONLINE" p secret-words)   # a passphrase-protected online key
R=$(newkey "$OFFLINE" r)               # the offline recovery key
GNUPGHOME=$OFFLINE gpg --batch --export "$R" | gpg --batch --import 2>/dev/null

# keyring <name> [rec=<fpr>] [rot=<fpr>] <fingerprint...>: a keyring folder,
# as in test-keys.sh; prints its keyring file.
keyring() {
  local d="$T/$1"; shift
  mkdir -p "$d"
  : > "$d/$KEYRING_BASENAME"
  for k in "$@"; do
    case $k in
      rec=*) printf '%s\n' "${k#rec=}" > "$d/$MARKER_RECOVERY" ;;
      rot=*) printf '%s\n' "${k#rot=}" > "$d/$MARKER_ROTATION" ;;
      *) gpg --batch --export "$k" >> "$d/$KEYRING_BASENAME" ;;
    esac
  done
  printf '%s\n' "$d/$KEYRING_BASENAME"
}
KR=$(keyring main rec="$R" "$A" "$R")
KR_ROT=$(keyring rotation rot="$B" "$A" "$B")
KR_P=$(keyring protected "$P")
printf 'secret-words\n' > "$T/passphrase"
: > "$T/empty-passphrase"

# deb <dir> <package> <version>: a stand-in package.
deb() {
  local stage="$T/stage-$2-$3"
  mkdir -p "$stage/DEBIAN" "$1"
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: t <t@example.invalid>\nDescription: d\n d\n' \
    "$2" "$3" > "$stage/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$stage" "$1/$2_$3_all.deb" >/dev/null
}
deb "$T/debs" pwsh 7.7.1-1
deb "$T/debs" pwsh-preview '7.8.0~preview.1-1'
deb "$T/debs" "$KEYRING_PACKAGE" 1
for v in 1 2 3 4 5 6; do deb "$T/debs$v" pwsh "7.7.$((v + 1))-1"; done

# Git, isolated from the user's configuration (no signing, no hooks).
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --global user.name "Test Author"
git config --global user.email "test@example.invalid"
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global tag.gpgsign false
WORK=$T/work REMOTE=$T/remote.git OTHER=$T/other
git init -q --bare "$REMOTE"
git init -q "$WORK"
mkdir -p "$WORK/.github/workflows"
echo 'name: w' > "$WORK/.github/workflows/w.yaml"
echo one > "$WORK/file"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m one
git -C "$WORK" remote add origin "file://$REMOTE"
git -C "$WORK" push -q origin main
HEAD1=$(git -C "$WORK" rev-parse HEAD)
git clone -q "file://$REMOTE" "$OTHER"

# rt <command> <argument...>: release-tags.sh in the work repository.
rt() { (cd "$WORK" && bash "$RT" "$@"); }
# with <NAME=value...> -- <command> <argument...>: the command (a function
# too) with those variables set, in a subshell.
with() (
  while [ "$1" != -- ]; do export "${1?}"; shift; done
  shift
  "$@"
)
# packages_of <debs-dir>: a Packages file listing each .deb's package and version.
packages_of() {
  local f
  for f in "$1"/*.deb; do dpkg-deb -f "$f" Package Version; echo; done
}
# rt_sign <debs-dir> <commit>: tags for the packages that have none, as
# update.yaml makes them: payloads (no key), sign-payloads (the key, given the
# index), assemble (no key).
rt_sign() {
  local w id
  w=$(mktemp -d -p "$T")
  id=$(in_work rev-parse --verify --quiet "$2^{commit}") || { echo "ERROR: $2 is not a commit" >&2; return 1; }
  rt payloads "$1" "$2" "$w/payloads" || return
  packages_of "$1" > "$w/Packages"
  rt sign-payloads "$w/payloads" "$id" "$w/signed" "$w/Packages" || return
  rt assemble "$w/signed"
}
# as <keyring> <signer> <command...>: with KEYRING_FILE and SIGN_KEY.
as() { KEYRING_FILE=$1 SIGN_KEY=$2 "${@:3}"; }
in_work() { git -C "$WORK" "$@"; }
tag_object() { in_work rev-parse --verify --quiet "refs/tags/$1"; }
has_tag() { tag_object "$1" >/dev/null; }
remote_tag() { git --git-dir="$REMOTE" rev-parse --verify --quiet "refs/tags/$1"; }
has_remote_tag() { remote_tag "$1" >/dev/null; }
# make_tag <ref> <name-in-object> <object> <type> <home> <key|-> [tamper|double]:
# a tag object built by hand, signed by <key> from <home> unless '-'.
make_tag() {
  local ref=$1 name=$2 object=$3 type=$4 home=$5 key=$6 mode=${7:-} p=$T/mk-payload s=$T/mk-signature
  printf 'object %s\ntype %s\ntag %s\ntagger t <t@example.invalid> 1700000000 +0000\n\nmessage\n' \
    "$object" "$type" "$name" > "$p"
  : > "$s"
  if [ "$key" != - ]; then
    GNUPGHOME=$home gpg --batch --yes --local-user "$key" --armor --detach-sign -o "$s" "$p"
  fi
  case $mode in
    tamper) printf 'object %s\ntype %s\ntag %s\ntagger t <t@example.invalid> 1700000000 +0000\n\nmassage\n' \
              "$object" "$type" "$name" > "$p" ;;
    double) cat "$s" "$s" > "$s.2" && mv "$s.2" "$s" ;;
  esac
  in_work update-ref "refs/tags/$ref" "$(cat "$p" "$s" | in_work mktag)"
}

echo "== name"
expect accept "a pwsh package"                 rt name "$T/debs/pwsh_7.7.1-1_all.deb"
check  "  ... is pwsh-7.7.1-1"                  same "$(cat "$T/out.log")" pwsh-7.7.1-1
expect accept "a pwsh-preview package"          rt name "$T/debs/pwsh-preview_7.8.0~preview.1-1_all.deb"
check  "  ... has '~' as '-'"                   same "$(cat "$T/out.log")" pwsh-preview-7.8.0-preview.1-1
expect refuse "the keyring package"             rt name "$T/debs/${KEYRING_PACKAGE}_1_all.deb"

echo "== sign"
expect accept "sign the packages on a commit"   as "$KR" "$A" rt_sign "$T/debs" HEAD
for tag in pwsh-7.7.1-1 pwsh-preview-7.8.0-preview.1-1; do
  check "  $tag is an annotated tag"            same "$(in_work cat-file -t "refs/tags/$tag")" tag
  check "  ... on the commit"                   same "$(in_work rev-parse "refs/tags/$tag^{commit}")" "$HEAD1"
  check "  ... tagged by github-actions[bot]"   same "$(in_work for-each-ref --format='%(taggername) %(taggeremail)' "refs/tags/$tag")" \
                                                     "$GITHUB_ACTIONS_BOT_LOGIN <$GITHUB_ACTIONS_BOT_EMAIL>"
  expect accept "  ... verifies, signed by the online key" as "$KR" "$A" rt verify "$tag"
  check "  ... names the online key"            same "$(cat "$T/out.log")" "$A"
done
check  "  no tag for the keyring package"       same "$(in_work tag -l "$KEYRING_PACKAGE*")" ""
# What SECURITY.md tells users to do: import the published key into their
# own gpg home, then git tag -v.
gpg --batch --import "$KR" 2>/dev/null
GNUPGHOME=$USER_HOME gpg --batch --import "$KR" 2>/dev/null
expect accept "git tag -v with the published key (the user's check)" \
  env GNUPGHOME="$USER_HOME" git -C "$WORK" tag -v pwsh-7.7.1-1
check  "  ... reports a good signature by it"   grep -q "Good signature from \"a <a@example.invalid>\"" "$T/err.log"
before=$(tag_object pwsh-7.7.1-1)
expect accept "sign again"                      as "$KR" "$A" rt_sign "$T/debs" HEAD
check  "  ... leaves the existing tag as it is" same "$(tag_object pwsh-7.7.1-1)" "$before"
expect accept "the next key, during a rotation" as "$KR_ROT" "$B" rt_sign "$T/debs1" HEAD
expect refuse "a stray key"                     as "$KR" "$C" rt_sign "$T/debs2" HEAD
check  "  ... leaves no tag"                    not has_tag pwsh-7.7.3-1
expect refuse "the recovery key"                with GNUPGHOME="$OFFLINE" KEYRING_FILE="$KR" SIGN_KEY="$R" -- rt_sign "$T/debs2" HEAD
check  "  ... leaves no tag"                    not has_tag pwsh-7.7.3-1
expect refuse "a protected key without GPG_PASSPHRASE_FILE" as "$KR_P" "$P" rt_sign "$T/debs2" HEAD
expect refuse "a protected key with an empty GPG_PASSPHRASE_FILE" \
  with GPG_PASSPHRASE_FILE="$T/empty-passphrase" KEYRING_FILE="$KR_P" SIGN_KEY="$P" -- rt_sign "$T/debs2" HEAD
check  "  ... leaves no tag"                    not has_tag pwsh-7.7.3-1
gpgconf --kill gpg-agent   # forget a cached passphrase
expect accept "a protected key with GPG_PASSPHRASE_FILE" \
  with GPG_PASSPHRASE_FILE="$T/passphrase" KEYRING_FILE="$KR_P" SIGN_KEY="$P" -- rt_sign "$T/debs2" HEAD
expect refuse "no SIGN_KEY"                     with KEYRING_FILE="$KR" -- rt_sign "$T/debs3" HEAD
expect refuse "not a commit"                    as "$KR" "$A" rt_sign "$T/debs3" no-such-commit
check  "  ... leaves no tag"                    not has_tag pwsh-7.7.4-1

echo "== verify"
in_work tag lightweight-1
in_work tag -a -m unsigned unsigned-1
make_tag renamed-1 pwsh-7.7.1-1 "$HEAD1" commit "$ONLINE" "$A"
make_tag tampered-1 tampered-1 "$HEAD1" commit "$ONLINE" "$A" tamper
make_tag double-1 double-1 "$HEAD1" commit "$ONLINE" "$A" double
make_tag recovery-1 recovery-1 "$HEAD1" commit "$OFFLINE" "$R"
make_tag stray-1 stray-1 "$HEAD1" commit "$ONLINE" "$C"
make_tag tree-1 tree-1 "$(in_work rev-parse "HEAD^{tree}")" tree "$ONLINE" "$A"
make_tag good-1 good-1 "$HEAD1" commit "$ONLINE" "$A"
expect accept "a tag made by hand the same way" as "$KR" "$A" rt verify good-1
expect refuse "a lightweight tag"               as "$KR" "$A" rt verify lightweight-1
expect refuse "an unsigned annotated tag"       as "$KR" "$A" rt verify unsigned-1
expect refuse "a tag object named otherwise"    as "$KR" "$A" rt verify renamed-1
expect refuse "an altered message"              as "$KR" "$A" rt verify tampered-1
expect refuse "two signatures"                  as "$KR" "$A" rt verify double-1
expect refuse "signed by the recovery key"      as "$KR" "$A" rt verify recovery-1
expect refuse "signed by a stray key"           as "$KR" "$A" rt verify stray-1
expect refuse "a tag of a tree"                 as "$KR" "$A" rt verify tree-1
expect refuse "no such tag"                     as "$KR" "$A" rt verify no-such-tag

echo "== push"
expect accept "push a signed tag"               as "$KR" "$A" rt push pwsh-7.7.1-1 origin
check  "  ... the remote has the same object"   same "$(remote_tag pwsh-7.7.1-1)" "$(tag_object pwsh-7.7.1-1)"
expect accept "push it again: nothing to do"    as "$KR" "$A" rt push pwsh-7.7.1-1 origin
check  "  ... says so"                          grep -q 'has pwsh-7.7.1-1 already' "$T/err.log"
expect refuse "an unsigned tag"                 as "$KR" "$A" rt push unsigned-1 origin
check  "  ... is not pushed"                    not has_remote_tag unsigned-1
# The remote holds another object under the name of a local tag.
as "$KR" "$A" rt_sign "$T/debs4" HEAD 2>/dev/null
in_work push -q origin good-1
git --git-dir="$REMOTE" update-ref refs/tags/pwsh-7.7.5-1 "$(remote_tag good-1)"
expect refuse "the remote has another tag of that name" as "$KR" "$A" rt push pwsh-7.7.5-1 origin
# main moves on without a workflow change: still pushed.
as "$KR" "$A" rt_sign "$T/debs5" HEAD 2>/dev/null
echo two > "$OTHER/file"
git -C "$OTHER" commit -q -am two
git -C "$OTHER" push -q origin main
expect accept "main moved, the same workflows"  as "$KR" "$A" rt push pwsh-7.7.6-1 origin
check  "  ... pushed"                           has_remote_tag pwsh-7.7.6-1
# main moves on with a workflow change: GitHub would refuse the token's push.
as "$KR" "$A" rt_sign "$T/debs6" HEAD 2>/dev/null
echo 'name: w2' > "$OTHER/.github/workflows/w.yaml"
git -C "$OTHER" commit -q -am three
git -C "$OTHER" push -q origin main
expect_status 3 "main moved with a workflow change: deferred (exit 3)" as "$KR" "$A" rt push pwsh-7.7.7-1 origin
check  "  ... not pushed"                       not has_remote_tag pwsh-7.7.7-1

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all release tag tests passed"
