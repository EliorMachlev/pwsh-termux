# shellcheck shell=bash
# Shared constants and helpers for the scripts in scripts/. Sourced, never run:
#
#   source "$(dirname "$0")/lib/common.sh"
#
# It exports nothing and changes no shell option or umask: each script keeps
# its own `set -euo pipefail` (and `umask 022` where it packages files).
# Constants live here only when a helper below uses them; a constant that one
# script needs stays in that script.

# ---------------------------------------------------------------------------
# Locations and names
# ---------------------------------------------------------------------------

SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCRIPTS_DIR
REPO_ROOT=$(cd "$SCRIPTS_DIR/.." && pwd)
readonly REPO_ROOT
# The log prefix: the running script's name without .sh ("build-repo").
SCRIPT_NAME=$(basename "$0" .sh)
readonly SCRIPT_NAME

readonly EXIT_FAILURE=1

readonly PROJECT_NAME=pwsh-termux
readonly DEFAULT_TERMUX_PREFIX=/data/data/com.termux/files/usr

# The public keyring users trust (keys/), and where the keyring package
# installs it.
readonly KEYRING_BASENAME=pwsh-termux-archive-keyring.gpg
readonly KEYRING_PACKAGE=pwsh-termux-keyring
readonly KEYS_DIR=$REPO_ROOT/keys
readonly DEFAULT_KEYRING_FILE=$KEYS_DIR/$KEYRING_BASENAME
readonly KEYRING_INSTALL_SUBDIR=share/keyrings
readonly KEYRING_DEB_MEMBER=.$DEFAULT_TERMUX_PREFIX/$KEYRING_INSTALL_SUBDIR/$KEYRING_BASENAME

# Marker files next to the keyring file: each names one key by fingerprint.
readonly MARKER_RECOVERY=RECOVERY   # the offline recovery key
readonly MARKER_ROTATION=ROTATION   # the next online key, during a planned rotation

# Key roles, as check-keys.sh prints them ("<fingerprint> <role>").
readonly ROLE_CURRENT=current       # the online key that signs
readonly ROLE_NEXT=next             # the online key a planned rotation moves to
readonly ROLE_RECOVERY=recovery     # the offline key; never signs in CI

# The apt repository's layout (build-repo.sh writes it).
readonly APT_SUITE=stable
readonly APT_COMPONENT=main
readonly APT_ARCH=aarch64
readonly PUBLISHED_KEY_GPG=$PROJECT_NAME.gpg          # the keyring file, binary
readonly PUBLISHED_KEY_ASC=$PROJECT_NAME.asc          # the keyring file, armored
readonly PUBLISHED_KEYRING_DEB=$KEYRING_PACKAGE.deb   # the keyring package, fixed name

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# log <message...>: a progress line on stderr, prefixed with the script name.
log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2; }

# die <message...>: an error line on stderr, then exit 1.
die() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit "$EXIT_FAILURE"; }

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

# sha256_of <file>: the file's SHA-256, lower-case hex.
sha256_of() { sha256sum < "$1" | cut -d' ' -f1; }

# file_size <file>: the file's size in bytes.
file_size() { stat -c %s "$1"; }

# deb_ships_keyring <deb> <keyring-file>: true if the package installs exactly
# that keyring file, byte for byte.
deb_ships_keyring() {
  dpkg-deb --fsys-tarfile "$1" | tar -xOf - "$KEYRING_DEB_MEMBER" | cmp -s - "$2"
}

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

# is_production_keyring <file>: true if it is keys/pwsh-termux-archive-keyring.gpg.
is_production_keyring() { [ "$1" -ef "$DEFAULT_KEYRING_FILE" ]; }

# is_allowed_in_keys_dir <file-name>: true for the files keys/ may hold.
is_allowed_in_keys_dir() {
  case $1 in
    "$KEYRING_BASENAME" | "$MARKER_RECOVERY" | "$MARKER_ROTATION") return 0 ;;
    *) return 1 ;;
  esac
}

# primary_fingerprints <keyring-file>: the fingerprint of each primary key
# (the fpr line after each pub line, not a subkey's), one per line.
primary_fingerprints() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null \
    | awk -F: '$1 == "pub" {want = 1; next} $1 == "fpr" && want {print $10; want = 0}'
}

# secret_key_fingerprint <key-id>: the fingerprint of the first secret key
# that matches, from the current gpg home. Fails as gpg does if none matches.
secret_key_fingerprint() {
  gpg --batch --list-secret-keys --with-colons -- "$1" \
    | awk -F: '$1 == "sec" {want = 1; next} $1 == "fpr" && want {print $10; exit}'
}

# check_keyring <keyring-file>: run check-keys.sh on it; prints its
# "<fingerprint> <role>" lines and fails if the keyring breaks the key rules.
check_keyring() { bash "$SCRIPTS_DIR/check-keys.sh" "$1"; }

# fingerprints_with_role <role...>: from check-keys.sh lines on stdin, the
# fingerprints of the keys that have any of the roles.
fingerprints_with_role() {
  awk -v roles="$*" '
    BEGIN { n = split(roles, list, " "); for (i = 1; i <= n; i++) wanted[list[i]] = 1 }
    $2 in wanted { print $1 }'
}

# online_fingerprints: from check-keys.sh lines on stdin, the keys that may
# sign online (the current key and, during a rotation, the next one).
online_fingerprints() { fingerprints_with_role "$ROLE_CURRENT" "$ROLE_NEXT"; }

# recovery_fingerprint <keyring-file>: the recovery key that keys/RECOVERY
# names, or nothing. Fails if the keyring breaks the key rules.
recovery_fingerprint() { check_keyring "$1" | fingerprints_with_role "$ROLE_RECOVERY"; }

# require_recovery_fingerprint <keyring-file>: as recovery_fingerprint, but
# dies if there is no recovery key.
require_recovery_fingerprint() {
  local keyring_file=$1 fingerprint
  fingerprint=$(recovery_fingerprint "$keyring_file") || return
  [ -n "$fingerprint" ] || die "no recovery key: keys/$MARKER_RECOVERY is not set up"
  printf '%s\n' "$fingerprint"
}

# read_fingerprint_marker <file>: the fingerprint a marker file names, or
# nothing if the file is absent. Dies unless it is a regular file of one line
# holding 40 upper-case hex digits.
read_fingerprint_marker() {
  local marker_file=$1 fingerprint
  [ -e "$marker_file" ] || return 0
  [ -f "$marker_file" ] || die "$marker_file is not a regular file"
  [ "$(wc -l < "$marker_file")" -eq 1 ] || die "$marker_file must be one line: a fingerprint"
  fingerprint=$(tr -d '[:space:]' < "$marker_file")
  [[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]] \
    || die "$marker_file does not hold a fingerprint (40 upper-case hex digits)"
  printf '%s\n' "$fingerprint"
}

# ---------------------------------------------------------------------------
# Signing and verifying the repository index
# ---------------------------------------------------------------------------

# sign_release <dist-dir> <gpg-option...>: sign <dist-dir>/Release as
# InRelease (clearsigned) and Release.gpg (detached), with the given options
# (which choose the key).
sign_release() {
  local dist_dir=$1; shift
  gpg "$@" --clearsign -o "$dist_dir/InRelease" "$dist_dir/Release"
  gpg "$@" -abs -o "$dist_dir/Release.gpg" "$dist_dir/Release"
}

# gpgv_quiet <keyring-file> <gpgv-argument...>: verify as apt does, against
# that keyring file alone, without gpgv's report on stderr.
gpgv_quiet() {
  local keyring_file=$1; shift
  gpgv --keyring "$keyring_file" "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# The apt repository's layout
# ---------------------------------------------------------------------------

# repo_dist_dir <repo-dir>: dists/<suite>, where Release and its signatures are.
repo_dist_dir() { printf '%s\n' "$1/dists/$APT_SUITE"; }

# repo_index_subdir: the Packages folder, relative to the dist folder.
repo_index_subdir() { printf '%s\n' "$APT_COMPONENT/binary-$APT_ARCH"; }

# repo_pool_subdir <package>: the package's pool folder, relative to the repo.
repo_pool_subdir() { printf '%s\n' "pool/$APT_COMPONENT/$1"; }

# repo_key_file <repo-dir>: the published keyring file, binary (/pwsh-termux.gpg).
repo_key_file() { printf '%s\n' "$1/$PUBLISHED_KEY_GPG"; }

# repo_armored_key_file <repo-dir>: the same keyring, armored (/pwsh-termux.asc).
repo_armored_key_file() { printf '%s\n' "$1/$PUBLISHED_KEY_ASC"; }

# repo_keyring_deb <repo-dir>: the keyring package under its fixed name.
repo_keyring_deb() { printf '%s\n' "$1/$PUBLISHED_KEYRING_DEB"; }
