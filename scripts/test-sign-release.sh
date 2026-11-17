#!/usr/bin/env bash
# Tests of the split signing path, offline: throwaway Ed25519 keys, stand-in
# packages, a local git repository, no network and no real key. Uses the
# test-only KEYRING_FILE.
#
#   signing-bundle.sh   pack and unpack round trip; refuses a path outside
#                       the whitelist, a link, a non-empty folder, too many
#                       files, and something that is not base64
#   sign-release.sh     sign: signs a fresh Release that lists its Packages
#                       and the verified keyring package; refuses a stray
#                       key, the recovery key, a wrong keyring digest, a
#                       Packages file that Release does not list, a stale
#                       Release. install: accepts the signed index for the
#                       repository it was built from; refuses another
#                       Release, an altered index file, an altered signature
#   release-tags.sh     payloads, sign-payloads, assemble: the same tag as
#                       `sign` makes; refuses a payload for another commit,
#                       an altered payload, an old one, a tag name that is
#                       not pwsh or pwsh-preview
#
# Usage: test-sign-release.sh
set -euo pipefail
umask 022
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SR=$SCRIPTS_DIR/sign-release.sh SB=$SCRIPTS_DIR/signing-bundle.sh RT=$SCRIPTS_DIR/release-tags.sh
unset KEYRING_FILE SIGN_KEY GPG_PASSPHRASE_FILE KEYRING_DEB_SHA256 VERIFIED_DEB_SHA256S GIT_DIR GIT_WORK_TREE
ONLINE=$T/online OFFLINE=$T/offline
mkdir -m 700 "$ONLINE" "$OFFLINE"
export GNUPGHOME=$ONLINE

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>
expect() {
  local want=$1 what=$2 got=0; shift 2
  "$@" >"$T/out.log" 2>"$T/err.log" || got=$?
  if { [ "$want" = accept ] && [ "$got" -eq 0 ]; } || { [ "$want" = refuse ] && [ "$got" -eq "$EXIT_FAILURE" ]; }; then
    pass "$what"
    if [ "$got" -ne 0 ]; then printf '        %s\n' "$(grep -E 'ERROR' "$T/err.log" | tail -1)"; fi
  else
    fail "$what (exit $got)"; cat "$T/out.log" "$T/err.log"
  fi
}
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }

newkey() {
  GNUPGHOME=$1 gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$2 <$2@example.invalid>" ed25519 sign never 2>/dev/null
  GNUPGHOME=$1 gpg --batch --list-secret-keys --with-colons "$2@example.invalid" 2>/dev/null \
    | awk -F: '$1 == "fpr" {print $10; exit}'
}
A=$(newkey "$ONLINE" a)
C=$(newkey "$ONLINE" c)
R=$(newkey "$OFFLINE" r)
GNUPGHOME=$OFFLINE gpg --batch --export "$R" | gpg --batch --import 2>/dev/null

# The keyring: the online key A, and the recovery key R named by RECOVERY.
mkdir "$T/keys"
{ gpg --batch --export "$A"; gpg --batch --export "$R"; } > "$T/keys/$KEYRING_BASENAME"
printf '%s\n' "$R" > "$T/keys/$MARKER_RECOVERY"
export KEYRING_FILE=$T/keys/$KEYRING_BASENAME

deb() {
  local stage="$T/stage-$2-$3"
  mkdir -p "$stage/DEBIAN" "$1"
  printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: t <t@example.invalid>\nDescription: d\n d\n' \
    "$2" "$3" > "$stage/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$stage" "$1/$2_$3_all.deb" >/dev/null
}
deb "$T/debs" pwsh 7.7.1-1
deb "$T/debs" pwsh-preview '7.8.0~preview.1-1'
bash "$SCRIPTS_DIR/build-keyring.sh" "$T/debs" >/dev/null 2>&1
KEYRING_DEB_SHA256=$(sha256_of "$T/debs/${KEYRING_PACKAGE}"_*_all.deb)
export KEYRING_DEB_SHA256
VERIFIED_DEB_SHA256S=$(for f in "$T"/debs/*.deb; do sha256_of "$f"; done)
export VERIFIED_DEB_SHA256S

# --- the unsigned index, as the assemble job writes it
bash "$SCRIPTS_DIR/build-repo.sh" "$T/debs" "$T/repo" >/dev/null 2>&1
DIST=$T/repo/dists/$APT_SUITE
mkdir "$T/in"
cp "$DIST/Release" "$DIST/$(repo_index_subdir)/Packages" "$T/in/"
as_a() { SIGN_KEY=$A "$@"; }

# --- signing-bundle.sh
mkdir -p "$T/b/tags"; echo r > "$T/b/Release"; echo p > "$T/b/tags/pwsh-1.payload"
bash "$SB" pack "$T/b" > "$T/bundle.b64"
mkdir "$T/b-out"
expect accept "bundle: unpack" bash -c "bash '$SB' unpack '$T/b-out' < '$T/bundle.b64'"
check "bundle: round trip" diff -r "$T/b" "$T/b-out"
mkdir "$T/b-out2"; echo x > "$T/b-out2/x"
expect refuse "bundle: a non-empty folder" bash -c "bash '$SB' unpack '$T/b-out2' < '$T/bundle.b64'"
mkdir "$T/evil"; echo x > "$T/evil/other"
expect refuse "bundle: pack refuses a name outside the whitelist" bash "$SB" pack "$T/evil"
mkdir "$T/evil2"; ln -s /etc/passwd "$T/evil2/Release"
tar -C "$T/evil2" -czf - Release | base64 -w0 > "$T/link.b64"
mkdir "$T/b-out3"
expect refuse "bundle: unpack refuses a link" bash -c "bash '$SB' unpack '$T/b-out3' < '$T/link.b64'"
mkdir "$T/evil3"; echo x > "$T/evil3/x"
tar -C "$T/evil3" --transform 's,^x$,../escape,' -czf - x | base64 -w0 > "$T/path.b64"
mkdir "$T/b-out4"
expect refuse "bundle: unpack refuses a path outside the folder" bash -c "bash '$SB' unpack '$T/b-out4' < '$T/path.b64'"
mkdir "$T/b-out5"
expect refuse "bundle: unpack refuses what is not base64" bash -c "echo '!!!' | bash '$SB' unpack '$T/b-out5'"
mkdir "$T/b-empty"
expect refuse "bundle: pack refuses an empty folder" bash "$SB" pack "$T/b-empty"
mkdir "$T/many"; for i in $(seq 1 41); do echo x > "$T/many/$i"; done
tar -C "$T/many" -czf - . | base64 -w0 > "$T/many.b64"
mkdir "$T/b-out6"
expect refuse "bundle: unpack refuses more than 40 files" bash -c "bash '$SB' unpack '$T/b-out6' < '$T/many.b64'"
mkdir "$T/big"; head -c 2100000 /dev/zero > "$T/big/Release"
tar -C "$T/big" -czf - Release | base64 -w0 > "$T/big.b64"
mkdir "$T/b-out7"
expect refuse "bundle: unpack refuses more than 2000000 bytes" bash -c "bash '$SB' unpack '$T/b-out7' < '$T/big.b64'"
expect refuse "bundle: no sub-command" bash "$SB"
expect refuse "sign-release: no sub-command" bash "$SR"

# --- sign-release.sh sign
expect accept "sign: a fresh Release with the verified keyring package" as_a bash "$SR" sign "$T/in" "$T/signed"
check "sign: InRelease and Release.gpg verify (gpgv)" bash -c "gpgv --keyring '$KEYRING_FILE' '$T/signed/InRelease' 2>/dev/null && gpgv --keyring '$KEYRING_FILE' '$T/signed/Release.gpg' '$T/signed/Release' 2>/dev/null"
expect refuse "sign: a stray key" env SIGN_KEY="$C" bash "$SR" sign "$T/in" "$T/s2"
expect refuse "sign: the recovery key (its secret in the gpg home)" env GNUPGHOME="$OFFLINE" SIGN_KEY="$R" bash "$SR" sign "$T/in" "$T/s3"
cp -r "$ONLINE" "$T/both"; chmod 700 "$T/both"
GNUPGHOME=$OFFLINE gpg --batch --export-secret-keys "$R" | GNUPGHOME="$T/both" gpg --batch --import 2>/dev/null
expect refuse "sign: the online key, with the recovery secret in the same gpg home" env GNUPGHOME="$T/both" SIGN_KEY="$A" bash "$SR" sign "$T/in" "$T/s3b"
expect refuse "sign: no SIGN_KEY" bash "$SR" sign "$T/in" "$T/s4"
expect refuse "sign: another keyring digest" as_a env KEYRING_DEB_SHA256="$(printf 0%.0s {1..64})" bash "$SR" sign "$T/in" "$T/s5"
expect refuse "sign: no list of verified digests" as_a env -u VERIFIED_DEB_SHA256S bash "$SR" sign "$T/in" "$T/s6b"
expect refuse "sign: a .deb missing from the verified list" as_a env VERIFIED_DEB_SHA256S="$(head -n 2 <<<"$VERIFIED_DEB_SHA256S")" bash "$SR" sign "$T/in" "$T/s6c"
expect refuse "sign: a verified digest that is no package of the index" as_a env VERIFIED_DEB_SHA256S="$VERIFIED_DEB_SHA256S"$'\n'"$(printf 2%.0s {1..64})" bash "$SR" sign "$T/in" "$T/s6d"
expect refuse "sign: a verified list that is not digests" as_a env VERIFIED_DEB_SHA256S="not a digest" bash "$SR" sign "$T/in" "$T/s6e"
expect refuse "sign: no keyring digest" as_a env -u KEYRING_DEB_SHA256 bash "$SR" sign "$T/in" "$T/s6"
mkdir "$T/in-p"; cp "$T/in/Release" "$T/in-p/"; { cat "$T/in/Packages"; echo; echo "Package: extra"; } > "$T/in-p/Packages"
expect refuse "sign: a Packages file Release does not list" as_a bash "$SR" sign "$T/in-p" "$T/s7"
# Release listing a different Packages digest under SHA256: and the right one only under SHA512:
mkdir "$T/in-sec"; cp "$T/in/Packages" "$T/in-sec/"
sha=$(sha256_of "$T/in/Packages"); size=$(file_size "$T/in/Packages")
sed "s/^ $sha $size \(.*Packages\)$/ $(printf 0%.0s {1..64}) $size \1\r/" "$T/in/Release" > "$T/in-sec/Release"
printf 'SHA512:\n %s %s %s/Packages\n' "$sha" "$size" "$(repo_index_subdir)" >> "$T/in-sec/Release"
expect refuse "sign: Packages listed correctly only outside the SHA256 section" as_a bash "$SR" sign "$T/in-sec" "$T/s7b"
# the same, written with a tab after the colons
mkdir "$T/in-tab"
{ cat "$T/in/Packages"; printf '\nPackage:\t%s\nVersion: 99\nSHA256:\t%s\n' "$KEYRING_PACKAGE" "$(printf 0%.0s {1..64})"; } > "$T/in-tab/Packages"
tsha=$(sha256_of "$T/in-tab/Packages"); tsize=$(file_size "$T/in-tab/Packages")
sed "s/^ $sha $size / $tsha $tsize /" "$T/in/Release" > "$T/in-tab/Release"
expect refuse "sign: a second keyring stanza written with tabs" as_a env VERIFIED_DEB_SHA256S="$VERIFIED_DEB_SHA256S"$'\n'"$(printf 0%.0s {1..64})" bash "$SR" sign "$T/in-tab" "$T/s7d"
# a second keyring stanza with no SHA256 field, listed correctly by Release
mkdir "$T/in-nosum"
{ cat "$T/in/Packages"; printf '\nPackage: %s\nVersion: 99\nSHA512: 00\n' "$KEYRING_PACKAGE"; } > "$T/in-nosum/Packages"
nsha=$(sha256_of "$T/in-nosum/Packages"); nsize=$(file_size "$T/in-nosum/Packages")
sed "s/^ $sha $size / $nsha $nsize /" "$T/in/Release" > "$T/in-nosum/Release"
expect refuse "sign: a second keyring stanza with no SHA256 field" as_a bash "$SR" sign "$T/in-nosum" "$T/s7c"
mkdir "$T/in-old"; cp "$T/in/Packages" "$T/in-old/"
now=$(now_epoch); old=$((now - 3 * SECONDS_PER_DAY))
sed -e "s/^Date: .*/Date: $(release_date "$old")/" -e "s/^Valid-Until: .*/Valid-Until: $(release_date $((old + 14 * SECONDS_PER_DAY)))/" "$T/in/Release" > "$T/in-old/Release"
expect refuse "sign: a Release written days ago" as_a bash "$SR" sign "$T/in-old" "$T/s8"

# --- sign-release.sh install (into the repository the index was built from)
cp -r "$T/repo" "$T/repo-i"
expect accept "install: the signed index" bash "$SR" install "$T/signed" "$T/repo-i"
check "install: the repository verifies as apt will" gpgv --keyring "$KEYRING_FILE" "$T/repo-i/dists/$APT_SUITE/InRelease" 2>/dev/null
cp -r "$T/repo" "$T/repo-t"; echo tampered >> "$T/repo-t/dists/$APT_SUITE/$(repo_index_subdir)/Packages"
expect refuse "install: an altered index file" bash "$SR" install "$T/signed" "$T/repo-t"
cp -r "$T/signed" "$T/signed-r"; echo "X: y" >> "$T/signed-r/Release"
expect refuse "install: another Release than the signed one" bash "$SR" install "$T/signed-r" "$T/repo"
cp -r "$T/signed" "$T/signed-s"
printf 'junk\n' > "$T/signed-s/Release.gpg"
expect refuse "install: an altered signature" bash "$SR" install "$T/signed-s" "$T/repo"
cp -r "$T/signed" "$T/signed-m"; rm "$T/signed-m/InRelease"
expect refuse "install: a signed folder without InRelease" bash "$SR" install "$T/signed-m" "$T/repo"
expect refuse "install: a .deb missing from the verified list" env VERIFIED_DEB_SHA256S="$(head -n 2 <<<"$VERIFIED_DEB_SHA256S")" bash "$SR" install "$T/signed" "$T/repo"
expect refuse "install: another keyring digest" env KEYRING_DEB_SHA256="$(printf 1%.0s {1..64})" bash "$SR" install "$T/signed" "$T/repo"

# --- release-tags.sh payloads, sign-payloads, assemble
export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
git config --global user.name t; git config --global user.email t@example.invalid
git config --global init.defaultBranch main; git config --global commit.gpgsign false
git init -q "$T/work"; echo 1 > "$T/work/f"; git -C "$T/work" add -A; git -C "$T/work" commit -q -m one
HEAD1=$(git -C "$T/work" rev-parse HEAD)
git -C "$T/work" commit -q --allow-empty -m two
HEAD2=$(git -C "$T/work" rev-parse HEAD)
rt() { (cd "$T/work" && bash "$RT" "$@"); }
rt_a() { (cd "$T/work" && SIGN_KEY=$A bash "$RT" "$@"); }
expect accept "payloads: one per released package" rt payloads "$T/debs" "$HEAD1" "$T/pl"
check "payloads: pwsh and pwsh-preview, not the keyring package" test "$(find "$T/pl" -type f | wc -l)" -eq 2
expect accept "sign-payloads: its own payloads" rt_a sign-payloads "$T/pl" "$HEAD1" "$T/pl-signed"
expect accept "assemble: the signed tags" rt assemble "$T/pl-signed"
check "assemble: pwsh-7.7.1-1 is verified by git tag -v" git -C "$T/work" tag -v pwsh-7.7.1-1 2>/dev/null >/dev/null
check "assemble: pwsh-preview-7.8.0-preview.1-1 is verified by git tag -v" git -C "$T/work" tag -v pwsh-preview-7.8.0-preview.1-1 2>/dev/null >/dev/null
expect accept "payloads: nothing for tags that exist" rt payloads "$T/debs" "$HEAD1" "$T/pl-none"
check "payloads: ... and no file" test -z "$(ls -A "$T/pl-none")"
git -C "$T/work" tag -d pwsh-7.7.1-1 pwsh-preview-7.8.0-preview.1-1 >/dev/null
expect refuse "sign-payloads: a payload for another commit" rt_a sign-payloads "$T/pl" "$HEAD2" "$T/x1"
mkdir "$T/pl-alt"; sed 's/^tag pwsh-7.7.1-1$/tag pwsh-9.9.9-1/' "$T/pl/pwsh-7.7.1-1.payload" > "$T/pl-alt/pwsh-7.7.1-1.payload"
expect refuse "sign-payloads: an altered payload" rt_a sign-payloads "$T/pl-alt" "$HEAD1" "$T/x2"
mkdir "$T/pl-name"; cp "$T/pl/pwsh-7.7.1-1.payload" "$T/pl-name/evil-1.payload"
expect refuse "sign-payloads: a tag name that is not pwsh or pwsh-preview" rt_a sign-payloads "$T/pl-name" "$HEAD1" "$T/x3"
mkdir "$T/pl-old"; sed "s/ [0-9]\{10\} +0000$/ 1000000000 +0000/" "$T/pl/pwsh-7.7.1-1.payload" > "$T/pl-old/pwsh-7.7.1-1.payload"
expect refuse "sign-payloads: an old payload" rt_a sign-payloads "$T/pl-old" "$HEAD1" "$T/x4"
expect refuse "sign-payloads: a stray key" env SIGN_KEY="$C" bash -c "cd '$T/work' && bash '$RT' sign-payloads '$T/pl' '$HEAD1' '$T/x5'"
mkdir "$T/pl-nosig"; cp "$T/pl/pwsh-7.7.1-1.payload" "$T/pl-nosig/"
expect refuse "assemble: a payload with no signature" rt assemble "$T/pl-nosig"

if [ "$fails" -ne 0 ]; then echo "$fails test(s) failed"; exit 1; fi
echo "all signing tests passed"
