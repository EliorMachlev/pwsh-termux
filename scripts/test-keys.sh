#!/usr/bin/env bash
# Tests of the key rules and the publish and recovery checks (check-keys.sh,
# build-repo.sh, verify-attestation.sh, recovery-sign.sh,
# verify-recovery-repo.sh), and of the index's Valid-Until window (a daily
# re-sign changes InRelease only), with throwaway Ed25519 keys and a stub
# `gh` (real attestations exist only on GitHub). Runs on Termux and on CI; touches
# nothing outside a temporary folder. Uses the test-only KEYRING_FILE.
#
# Usage: test-keys.sh
set -euo pipefail
umask 022
source "$(dirname "$0")/lib/common.sh"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
unset KEYRING_FILE KEYRING_DEB_SHA256 SIGN_KEY SOURCE_DATE_EPOCH GPG_PASSPHRASE_FILE
# Two gpg homes, as in reality: the online keys (CI) and the offline
# recovery key (the maintainer's machine).
ONLINE=$T/online OFFLINE=$T/offline
mkdir -m 700 "$ONLINE" "$OFFLINE"
export GNUPGHOME=$ONLINE

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>&1; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    # the reason, so a refusal for the wrong reason is visible
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -E 'ERROR|Error' "$T/out.log" | tail -1)"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log"
  fi
}

# newkey <home> <name>: generate a key there and print its fingerprint.
newkey() {
  GNUPGHOME=$1 gpg --batch --passphrase '' --quick-generate-key "$2 <$2@example.invalid>" ed25519 sign never 2>/dev/null
  GNUPGHOME=$1 gpg --batch --list-secret-keys --with-colons "$2@example.invalid" 2>/dev/null \
    | awk -F: '$1 == "fpr" {print $10; exit}'
}
A=$(newkey "$ONLINE" a)       # the current online key
B=$(newkey "$ONLINE" b)       # the next online key
C=$(newkey "$ONLINE" c)       # a stray key
R=$(newkey "$OFFLINE" r)      # the offline recovery key
GNUPGHOME=$OFFLINE gpg --batch --export "$R" > "$T/recovery-public.gpg"
gpg --batch --import "$T/recovery-public.gpg" 2>/dev/null   # public half only, as keys/ has it

# keyring <name> [rec=<fpr>] [rot=<fpr>] <fingerprint...>: a keyring folder.
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
# kr <name>: the keyring file of a folder that keyring() made.
kr() { printf '%s\n' "$T/$1/$KEYRING_BASENAME"; }
ck() { bash "$SCRIPTS_DIR/check-keys.sh" "$1"; }

# A dummy package, so the repository has something besides the keyring.
mkdir -p "$T/dummy/DEBIAN"
printf 'Package: dummy\nVersion: 1\nArchitecture: aarch64\nMaintainer: t <t@example.invalid>\nDescription: d\n d\n' \
  > "$T/dummy/DEBIAN/control"
dpkg-deb --root-owner-group --build "$T/dummy" "$T/dummy_1_aarch64.deb" >/dev/null

# debs <keyring-file>: a folder with the dummy and a keyring package from it.
debs() {
  local d; d=$(mktemp -d -p "$T")
  cp "$T/dummy_1_aarch64.deb" "$d/"
  KEYRING_FILE=$1 bash "$SCRIPTS_DIR/build-keyring.sh" "$d" >/dev/null 2>&1
  printf '%s\n' "$d"
}
# publish <keyring-file> <signer> [debs-dir]: build-repo.sh as the publish job
# runs it, with the keyring package's digest as the verify job would pass it.
publish() {
  local keyring_file=$1 signer=$2 d=${3:-}
  [ -n "$d" ] || d=$(debs "$keyring_file")
  local deb=("$d"/"$KEYRING_PACKAGE"_*_all.deb)
  KEYRING_FILE=$keyring_file SIGN_KEY=$signer KEYRING_DEB_SHA256=$(sha256_of "${deb[0]}") \
    bash "$SCRIPTS_DIR/build-repo.sh" "$d" "$(mktemp -d -p "$T")/repo"
}

# publish_in <gpg-home> <keyring-file> <signer>: publish from another gpg home.
publish_in() { local GNUPGHOME=$1; export GNUPGHOME; publish "$2" "$3"; }

# verify_recovery <keyring-file> <repo-dir>: verify-recovery-repo.sh, as recover.yaml runs it.
verify_recovery() { env KEYRING_FILE="$1" bash "$SCRIPTS_DIR/verify-recovery-repo.sh" "$2"; }

echo "== check-keys.sh: shapes"
expect accept "the committed keys/"                       ck "$DEFAULT_KEYRING_FILE"
expect accept "{online}"                                  ck "$(keyring s1 "$A")"
expect accept "{online, recovery}"                        ck "$(keyring s2 rec="$R" "$A" "$R")"
expect accept "{online, next} with ROTATION"              ck "$(keyring s3 rot="$B" "$A" "$B")"
expect accept "{online, next, recovery} with both markers" ck "$(keyring s4 rec="$R" rot="$B" "$A" "$B" "$R")"
expect refuse "a stray second key, no marker"             ck "$(keyring s5 "$A" "$C")"
expect refuse "a stray key next to online and recovery"   ck "$(keyring s6 rec="$R" "$A" "$C" "$R")"
expect refuse "recovery key without keys/RECOVERY"        ck "$(keyring s7 "$A" "$R")"
expect refuse "keys/RECOVERY whose key is missing"        ck "$(keyring s8 rec="$R" "$A")"
expect refuse "ROTATION naming a key that is not there"   ck "$(keyring s9 rot="$C" "$A" "$B")"
expect refuse "stale ROTATION: its key is the only one"   ck "$(keyring s10 rot="$B" "$B")"
expect refuse "stale ROTATION next to the recovery key"   ck "$(keyring s11 rec="$R" rot="$B" "$B" "$R")"
expect refuse "ROTATION naming the recovery key"          ck "$(keyring s12 rec="$R" rot="$R" "$A" "$R")"
expect refuse "three online keys with a ROTATION"         ck "$(keyring s13 rot="$B" "$A" "$B" "$C")"
expect refuse "a marker that is not a fingerprint"        ck "$(keyring s14 rot=not-a-key "$A" "$B")"
GNUPGHOME=$OFFLINE gpg --batch --export-secret-keys "$R" > "$T/secret.gpg"
expect refuse "secret key material"                       ck "$T/secret.gpg"
gpg --batch --armor --export "$A" > "$T/armored.gpg"
expect refuse "an armored key"                            ck "$T/armored.gpg"

echo "== build-repo.sh: who may sign"
expect accept "{online}: the online key signs"            publish "$(kr s1)" "$A"
expect refuse "{online}: another key signs"               publish "$(kr s1)" "$B"
expect accept "{online, recovery}: the online key signs"  publish "$(kr s2)" "$A"
expect refuse "the recovery key as the signer" \
  publish_in "$OFFLINE" "$(kr s2)" "$R"
mkdir -m 700 "$T/leaky"
GNUPGHOME=$ONLINE gpg --batch --export-secret-keys "$A" | GNUPGHOME=$T/leaky gpg --batch --import 2>/dev/null
GNUPGHOME=$T/leaky gpg --batch --import "$T/secret.gpg" 2>/dev/null
expect refuse "the recovery key's secret in the CI gpg home" \
  publish_in "$T/leaky" "$(kr s2)" "$A"
expect accept "rotation step 1: the current key signs"    publish "$(kr s4)" "$A"
expect accept "rotation step 3: the next key signs"       publish "$(kr s4)" "$B"
expect refuse "rotation: a stray key signs"               publish "$(kr s3)" "$C"
expect refuse "a stray second key"                        publish "$(kr s5)" "$A"
expect refuse "a stale ROTATION"                          publish "$(kr s10)" "$B"
expect refuse "a ROTATION naming a missing key"           publish "$(kr s9)" "$A"
expect refuse "the production keys/ with a test signer"   publish "$DEFAULT_KEYRING_FILE" "$A"

echo "== build-repo.sh: which keyring package"
other=$(debs "$(keyring s15 "$B")")
expect refuse "a package that ships another key"          publish "$(kr s1)" "$A" "$other"
good=$(debs "$(kr s1)")
expect refuse "a package that is not the verified file" \
  env KEYRING_FILE="$(kr s1)" SIGN_KEY="$A" KEYRING_DEB_SHA256=0000 \
  bash "$SCRIPTS_DIR/build-repo.sh" "$good" "$T/repo-x"
expect refuse "a package without a verified digest" \
  env KEYRING_FILE="$(kr s1)" SIGN_KEY="$A" \
  bash "$SCRIPTS_DIR/build-repo.sh" "$good" "$T/repo-y"
expect accept "the verified package"                      publish "$(kr s1)" "$A" "$good"

echo "== verify-attestation.sh (stub gh)"
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$GH_STUB_ARGS"
exit "${GH_STUB_EXIT:-0}"
STUB
chmod 755 "$T/bin/gh"
export GH_STUB_ARGS="$T/gh.args"
deb=("$good"/"$KEYRING_PACKAGE"_*_all.deb)
sha=0123456789abcdef0123456789abcdef01234567
expect refuse "an unattested package (gh refuses)" \
  env PATH="$T/bin:$PATH" GH_STUB_EXIT=1 bash "$SCRIPTS_DIR/verify-attestation.sh" "${deb[0]}" "$sha"
expect accept "an attested package (gh accepts)" \
  env PATH="$T/bin:$PATH" GH_STUB_EXIT=0 bash "$SCRIPTS_DIR/verify-attestation.sh" "${deb[0]}" "$sha"
expect accept "gh pinned to the build workflow, the commit and hosted runners" \
  grep -q -- "--signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml --source-digest $sha --deny-self-hosted-runners" "$T/gh.args"
expect refuse "not a commit SHA" \
  env PATH="$T/bin:$PATH" bash "$SCRIPTS_DIR/verify-attestation.sh" "${deb[0]}" main

echo "== recovery: sign with the offline key, verify before deploying"
# After a compromise of A: keys/ becomes {B (new online), R}; the repository
# is built unsigned and signed offline with R.
new=$(keyring s16 rec="$R" "$B" "$R")
rd=$(debs "$new")
KEYRING_FILE=$new bash "$SCRIPTS_DIR/build-repo.sh" "$rd" "$T/rrepo" 2>/dev/null
rsign() { env -u CI -u GITHUB_ACTIONS GNUPGHOME="$OFFLINE" KEYRING_FILE="$1" bash "$SCRIPTS_DIR/recovery-sign.sh" "$2"; }
expect refuse "recovery-sign.sh in CI"                    env CI=true GNUPGHOME="$OFFLINE" KEYRING_FILE="$new" bash "$SCRIPTS_DIR/recovery-sign.sh" "$T/rrepo"
expect refuse "recovery-sign.sh without the offline secret" env -u CI -u GITHUB_ACTIONS KEYRING_FILE="$new" bash "$SCRIPTS_DIR/recovery-sign.sh" "$T/rrepo"
expect refuse "recovery-sign.sh without keys/RECOVERY"    rsign "$(kr s1)" "$T/rrepo"
expect accept "recovery-sign.sh signs and verifies"       rsign "$new" "$T/rrepo"
expect accept "verify-recovery-repo.sh on the result"     verify_recovery "$new" "$T/rrepo"
expect accept "the old keyring {A, R} accepts it (gpgv, as apt)" \
  gpgv --keyring "$(keyring s17 rec="$R" "$A" "$R")" "$(repo_dist_dir "$T/rrepo")/InRelease"
cp -r "$T/rrepo" "$T/online-signed"
gpg --batch --yes --local-user "$B" --clearsign -o "$(repo_dist_dir "$T/online-signed")/InRelease" "$(repo_dist_dir "$T/online-signed")/Release" 2>/dev/null
expect refuse "an index signed by the online key, not the recovery key" \
  verify_recovery "$new" "$T/online-signed"
cp -r "$T/rrepo" "$T/extra"
cp "$T/dummy_1_aarch64.deb" "$T/extra/$(repo_pool_subdir dummy)/extra.deb"
expect refuse "an unlisted file in pool/"                 verify_recovery "$new" "$T/extra"
cp -r "$T/rrepo" "$T/swapped"
printf 'x' >> "$T/swapped/$(repo_pool_subdir dummy)/dummy_1_aarch64.deb"
expect refuse "a package that does not match Packages"    verify_recovery "$new" "$T/swapped"
cp -r "$T/rrepo" "$T/oldkey"
cp "$(kr s1)" "$(repo_key_file "$T/oldkey")"
expect refuse "a published key file that is not keys/"    verify_recovery "$new" "$T/oldkey"

echo "== Valid-Until: a bounded window, and a re-sign changes InRelease only"
# publish_to <keyring-file> <signer> <debs-dir> <repo-dir>: publish, to a known folder.
publish_to() {
  local deb=("$3"/"$KEYRING_PACKAGE"_*_all.deb)
  KEYRING_FILE=$1 SIGN_KEY=$2 KEYRING_DEB_SHA256=$(sha256_of "${deb[0]}") \
    bash "$SCRIPTS_DIR/build-repo.sh" "$3" "$4"
}
# same_bytes <file> <file>, differ <file> <file>
same_bytes() { cmp -s "$1" "$2"; }
differ() { ! cmp -s "$1" "$2"; }
# window_is <release-file> <seconds>: Valid-Until - Date is exactly that.
# (A subshell, like the next one: the helpers die, which must not end the test.)
window_is() (
  date=$(release_field_epoch "$1" Date) && valid_until=$(release_field_epoch "$1" Valid-Until) \
    && [ $((valid_until - date)) -eq "$2" ]
)
# dates_well_formed <release-file>: both lines match apt's date format.
dates_well_formed() {
  grep -Eq "^Date: ${RELEASE_DATE_REGEX#^}" "$1" && grep -Eq "^Valid-Until: ${RELEASE_DATE_REGEX#^}" "$1"
}
# window_ok <release-file> <min-days-left>: check_release_window accepts it.
window_ok() ( check_release_window "$@" )
# signed_text_has <inrelease> <keyring-file> <line>: the signed text holds the line.
signed_text_has() { gpgv_quiet "$2" --output - "$1" | grep -qxF -- "$3"; }

expect accept "day 1: publish"                            publish_to "$(kr s1)" "$A" "$good" "$T/day1"
sleep 2   # a later run: Date and Valid-Until move on
expect accept "day 2: publish the same packages again"    publish_to "$(kr s1)" "$A" "$good" "$T/day2"
d1=$(repo_dist_dir "$T/day1") d2=$(repo_dist_dir "$T/day2") idx=$(repo_index_subdir)
expect accept "Release has Valid-Until"                   grep -q '^Valid-Until: ' "$d1/Release"
expect accept "Date and Valid-Until are RFC 1123 UTC dates" dates_well_formed "$d1/Release"
expect accept "Valid-Until is Date + $VALID_UNTIL_DAYS days" window_is "$d1/Release" $((VALID_UNTIL_DAYS * SECONDS_PER_DAY))
expect accept "the window starts now"                     window_ok "$d1/Release" $((VALID_UNTIL_DAYS - 1))
expect accept "Valid-Until is in the signed text (InRelease)" \
  signed_text_has "$d1/InRelease" "$(kr s1)" "Valid-Until: $(release_field "$d1/Release" Valid-Until)"
expect accept "a later run: Valid-Until moved on"         differ "$d1/Release" "$d2/Release"
expect accept "a later run: InRelease differs"            differ "$d1/InRelease" "$d2/InRelease"
expect accept "a later run: Release.gpg differs"          differ "$d1/Release.gpg" "$d2/Release.gpg"
for f in Packages Packages.gz Packages.xz; do
  if [ "$f" = Packages.xz ] && ! command -v xz >/dev/null; then echo "skip  $f (no xz here)"; continue; fi
  expect accept "a later run: $f is byte-identical"       same_bytes "$d1/$idx/$f" "$d2/$idx/$f"
done
for deb in "$T"/day1/pool/*/*/*.deb; do
  expect accept "a later run: ${deb##*/} is byte-identical" same_bytes "$deb" "$T/day2/${deb#"$T"/day1/}"
done
expect accept "a later run: the index verifies (gpgv, as apt)" gpgv_quiet "$(kr s1)" "$d2/InRelease"

# set_window <repo-dir> <Date-line-value> <Valid-Until-line-value|-> : rewrite
# Release's dates (- drops Valid-Until), as a hand-made or old Release would be.
set_window() {
  local release; release=$(repo_dist_dir "$1")/Release
  sed -i -e "s/^Date: .*/Date: $2/" -e '/^Valid-Until: /d' "$release"
  if [ "$3" != - ]; then sed -i "/^Date: /a Valid-Until: $3" "$release"; fi
}
# rresign <repo-dir>: sign its Release with the recovery key again.
rresign() {
  local dist; dist=$(repo_dist_dir "$1")
  GNUPGHOME=$OFFLINE gpg --batch --yes --local-user "$R" --clearsign -o "$dist/InRelease" "$dist/Release" 2>/dev/null
  GNUPGHOME=$OFFLINE gpg --batch --yes --local-user "$R" -abs -o "$dist/Release.gpg" "$dist/Release" 2>/dev/null
}
# windowed <name> <Date> <Valid-Until|->: a recovery-signed copy of rrepo with these dates.
windowed() {
  cp -r "$T/rrepo" "$T/$1"
  set_window "$T/$1" "$2" "$3"
  rresign "$T/$1"
  printf '%s\n' "$T/$1"
}
now=$(now_epoch) day=$SECONDS_PER_DAY
expect accept "recovery: a window with 13 days left" \
  verify_recovery "$new" "$(windowed w1 "$(release_date $((now - day)))" "$(release_date $((now + 13 * day)))")"
expect refuse "recovery: no Valid-Until" \
  verify_recovery "$new" "$(windowed w2 "$(release_date "$now")" -)"
expect refuse "recovery: Valid-Until more than $VALID_UNTIL_DAYS days after Date" \
  verify_recovery "$new" "$(windowed w3 "$(release_date "$now")" "$(release_date $((now + 30 * day)))")"
expect refuse "recovery: expired" \
  verify_recovery "$new" "$(windowed w4 "$(release_date $((now - 20 * day)))" "$(release_date $((now - 6 * day)))")"
expect refuse "recovery: fewer than $VALID_UNTIL_WARN_DAYS days left" \
  verify_recovery "$new" "$(windowed w5 "$(release_date $((now - 10 * day)))" "$(release_date $((now + 4 * day)))")"
expect refuse "recovery: a Date in the future" \
  verify_recovery "$new" "$(windowed w6 "$(release_date $((now + day)))" "$(release_date $((now + 10 * day)))")"
expect refuse "recovery: a Valid-Until that is not an RFC 1123 date" \
  verify_recovery "$new" "$(windowed w7 "$(release_date "$now")" "2099-01-01T00:00:00Z")"
expect refuse "recovery: a Valid-Until that is not a real day" \
  verify_recovery "$new" "$(windowed w8 "$(release_date "$now")" "Mon, 31 Feb 2099 00:00:00 UTC")"
KEYRING_FILE=$new bash "$SCRIPTS_DIR/build-repo.sh" "$rd" "$T/stale" 2>/dev/null
set_window "$T/stale" "$(release_date $((now - 10 * day)))" "$(release_date $((now + 4 * day)))"
expect refuse "recovery-sign.sh: a Release built too long ago" rsign "$new" "$T/stale"

echo
[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all passed"
