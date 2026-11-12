#!/usr/bin/env bash
# Tests of the key rules in check-keys.sh, build-repo.sh and
# verify-attestation.sh, with throwaway Ed25519 keys and a stub `gh` (real
# attestations exist only on GitHub). Runs on Termux and on CI; touches
# nothing outside a temporary folder. Uses the test-only KEYRING_FILE.
#
# Usage: test-keys.sh
set -euo pipefail
umask 022

HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export GNUPGHOME="$T/gnupg"
mkdir -m 700 "$GNUPGHOME"
unset KEYRING_FILE KEYRING_DEB_SHA256 SIGN_KEY SOURCE_DATE_EPOCH

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

newkey() {
  gpg --batch --passphrase '' --quick-generate-key "$1 <$1@example.invalid>" ed25519 sign never 2>/dev/null
  gpg --batch --list-secret-keys --with-colons "$1@example.invalid" 2>/dev/null | awk -F: '$1 == "fpr" {print $10; exit}'
}
A=$(newkey a)
B=$(newkey b)
C=$(newkey c)

# A keyring folder: keyring <name> <fingerprint...> [-- <marker content>]
keyring() {
  local d="$T/$1"; shift
  mkdir -p "$d"
  : > "$d/pwsh-termux-archive-keyring.gpg"
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    gpg --batch --export "$1" >> "$d/pwsh-termux-archive-keyring.gpg"; shift
  done
  if [ "${1:-}" = -- ]; then printf '%s\n' "$2" > "$d/ROTATION"; fi
  printf '%s\n' "$d/pwsh-termux-archive-keyring.gpg"
}

# A dummy package, so the repository has something besides the keyring.
mkdir -p "$T/dummy/DEBIAN"
printf 'Package: dummy\nVersion: 1\nArchitecture: aarch64\nMaintainer: t <t@example.invalid>\nDescription: d\n d\n' \
  > "$T/dummy/DEBIAN/control"
dpkg-deb --root-owner-group --build "$T/dummy" "$T/dummy_1_aarch64.deb" >/dev/null

# publish <keyring-file> <signer> [debs-dir]: build-repo.sh as the publish job
# runs it, with the keyring package's digest as the verify job would pass it.
publish() {
  local kr=$1 signer=$2 debs=${3:-}
  if [ -z "$debs" ]; then
    debs="$T/debs-$RANDOM"; mkdir -p "$debs"
    cp "$T/dummy_1_aarch64.deb" "$debs/"
    KEYRING_FILE=$kr bash "$HERE/build-keyring.sh" "$debs" >/dev/null
  fi
  local deb=("$debs"/pwsh-termux-keyring_*_all.deb)
  KEYRING_FILE=$kr SIGN_KEY=$signer KEYRING_DEB_SHA256=$(sha256sum < "${deb[0]}" | cut -d' ' -f1) \
    bash "$HERE/build-repo.sh" "$debs" "$T/repo-$RANDOM"
}

echo "== check-keys.sh"
expect accept "the committed keys/"                      bash "$HERE/check-keys.sh"
expect accept "one key, no marker"                      bash "$HERE/check-keys.sh" "$(keyring k1 "$A")"
expect refuse "two keys, no marker"                     bash "$HERE/check-keys.sh" "$(keyring k2 "$A" "$B")"
expect accept "two keys, marker names one of them"      bash "$HERE/check-keys.sh" "$(keyring k3 "$A" "$B" -- "$B")"
expect refuse "two keys, marker names neither"          bash "$HERE/check-keys.sh" "$(keyring k4 "$A" "$B" -- "$C")"
expect refuse "stale marker: one key and a marker"      bash "$HERE/check-keys.sh" "$(keyring k5 "$B" -- "$B")"
expect refuse "three keys with a marker"                bash "$HERE/check-keys.sh" "$(keyring k6 "$A" "$B" "$C" -- "$B")"
expect refuse "marker that is not a fingerprint"        bash "$HERE/check-keys.sh" "$(keyring k7 "$A" "$B" -- "not-a-key")"
gpg --batch --export-secret-keys "$A" > "$T/secret.gpg"
expect refuse "secret key material"                     bash "$HERE/check-keys.sh" "$T/secret.gpg"
gpg --batch --armor --export "$A" > "$T/armored.gpg"
expect refuse "armored key"                             bash "$HERE/check-keys.sh" "$T/armored.gpg"

echo "== build-repo.sh (signing)"
expect accept "steady state: signer is the one key"     publish "$T/k1/pwsh-termux-archive-keyring.gpg" "$A"
expect refuse "signer is not the key in keys/"          publish "$T/k1/pwsh-termux-archive-keyring.gpg" "$B"
expect refuse "two keys without a marker"               publish "$T/k2/pwsh-termux-archive-keyring.gpg" "$A"
expect accept "rotation, step 1: old key signs"         publish "$T/k3/pwsh-termux-archive-keyring.gpg" "$A"
expect accept "rotation, step 3: marked key signs"      publish "$T/k3/pwsh-termux-archive-keyring.gpg" "$B"
expect refuse "rotation: a third key signs"             publish "$T/k3/pwsh-termux-archive-keyring.gpg" "$C"
expect refuse "marker with a wrong fingerprint"         publish "$T/k4/pwsh-termux-archive-keyring.gpg" "$A"
expect refuse "stale marker"                            publish "$T/k5/pwsh-termux-archive-keyring.gpg" "$B"
expect refuse "the production keys/ with a test signer"  publish "$HERE/../keys/pwsh-termux-archive-keyring.gpg" "$A"

# Altered and unverified packages.
mkdir -p "$T/other"
cp "$T/dummy_1_aarch64.deb" "$T/other/"
KEYRING_FILE=$(keyring k8 "$B") bash "$HERE/build-keyring.sh" "$T/other" >/dev/null 2>&1
expect refuse "keyring package that ships another key" publish "$T/k1/pwsh-termux-archive-keyring.gpg" "$A" "$T/other"
mkdir -p "$T/good"
cp "$T/dummy_1_aarch64.deb" "$T/good/"
KEYRING_FILE=$T/k1/pwsh-termux-archive-keyring.gpg bash "$HERE/build-keyring.sh" "$T/good" >/dev/null 2>&1
expect refuse "keyring package that is not the verified file" \
  env KEYRING_FILE="$T/k1/pwsh-termux-archive-keyring.gpg" SIGN_KEY="$A" KEYRING_DEB_SHA256=0000 \
  bash "$HERE/build-repo.sh" "$T/good" "$T/repo-x"
expect refuse "keyring package without a verified digest" \
  env -u KEYRING_DEB_SHA256 KEYRING_FILE="$T/k1/pwsh-termux-archive-keyring.gpg" SIGN_KEY="$A" \
  bash "$HERE/build-repo.sh" "$T/good" "$T/repo-y"
expect accept "the same package with its verified digest" publish "$T/k1/pwsh-termux-archive-keyring.gpg" "$A" "$T/good"

echo "== verify-attestation.sh (stub gh)"
mkdir -p "$T/bin"
cat > "$T/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$GH_STUB_ARGS"
exit "${GH_STUB_EXIT:-0}"
STUB
export GH_STUB_ARGS="$T/gh.args"
chmod 755 "$T/bin/gh"
deb=("$T"/good/pwsh-termux-keyring_*_all.deb)
sha=0123456789abcdef0123456789abcdef01234567
expect refuse "unattested package (gh refuses)" \
  env PATH="$T/bin:$PATH" GH_STUB_EXIT=1 bash "$HERE/verify-attestation.sh" "${deb[0]}" "$sha"
expect accept "attested package (gh accepts)" \
  env PATH="$T/bin:$PATH" GH_STUB_EXIT=0 bash "$HERE/verify-attestation.sh" "${deb[0]}" "$sha"
expect accept "gh is pinned to the build workflow, the commit and hosted runners" \
  grep -q -- "--signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml --source-digest $sha --deny-self-hosted-runners" "$T/gh.args"
expect refuse "not a commit SHA" \
  env PATH="$T/bin:$PATH" bash "$HERE/verify-attestation.sh" "${deb[0]}" main

echo
[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all passed"
