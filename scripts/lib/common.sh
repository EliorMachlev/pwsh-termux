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
readonly PROJECT_GITHUB_URL=https://github.com/EliorMachlev/$PROJECT_NAME
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

# project_blob_url <path>: the file on GitHub, on main.
project_blob_url() { printf '%s\n' "$PROJECT_GITHUB_URL/blob/main/$1"; }

# project_commit_url <sha>: the commit on GitHub.
project_commit_url() { printf '%s\n' "$PROJECT_GITHUB_URL/commit/$1"; }

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

# ---------------------------------------------------------------------------
# Building packages reproducibly (build-deb.sh, build-keyring.sh)
# ---------------------------------------------------------------------------

# installed_size_kib <stage-dir>: Installed-Size as dpkg-gencontrol counts it
# (KiB per file, rounded up; one per directory or link), so it does not
# depend on the build machine's file system the way `du` does.
installed_size_kib() {
  find "$1" -mindepth 1 -printf '%y %s\n' \
    | awk '$1 == "f" {kb += int(($2 + 1023) / 1024); next} {kb += 1} END {print kb}'
}

# build_reproducible_deb <stage-dir> <deb> <dpkg-deb-option...>: build the
# package with every timestamp set to SOURCE_DATE_EPOCH (which the caller
# sets and exports; dpkg-deb also uses it for the archive's own members),
# root:root owners, and xz single-threaded (its multi-threaded output depends
# on the number of CPUs). The same staged files give the same bytes.
build_reproducible_deb() {
  local stage=$1 deb=$2; shift 2
  [[ "${SOURCE_DATE_EPOCH:-}" =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH is not set"
  find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  mkdir -p "$(dirname "$deb")"
  dpkg-deb --root-owner-group --threads-max=1 "$@" --build "$stage" "$deb" >&2
}

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
# The index's validity window (Date and Valid-Until in Release)
# ---------------------------------------------------------------------------

# apt refuses an index after its Valid-Until, so a stale (frozen) index cannot
# be replayed to users for longer than this. The daily update.yaml run
# re-signs the index, which moves the window on.
readonly VALID_UNTIL_DAYS=14
# Fewer days left than this is stale: the staleness monitor opens an issue,
# and a recovery-signed index with less is not signed or deployed.
readonly VALID_UNTIL_WARN_DAYS=7
# How far a Date may be ahead of this machine's clock (clock skew).
readonly RELEASE_CLOCK_SKEW_SECONDS=300
readonly SECONDS_PER_DAY=86400
# Date and Valid-Until as apt writes and reads them (RFC 1123, in UTC).
readonly RELEASE_DATE_FORMAT='%a, %d %b %Y %H:%M:%S UTC'
readonly RELEASE_DATE_REGEX='^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), [0-9]{2} (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} UTC$'

# now_epoch: the current time, seconds since the epoch.
now_epoch() { date -u +%s; }

# release_date <epoch>: that time as a Release date.
release_date() { LC_ALL=C date -u -d "@$1" +"$RELEASE_DATE_FORMAT"; }

# release_field <release-file> <field>: the value of a top-level field, or
# nothing.
release_field() {
  awk -v name="$2" 'index($0, name ": ") == 1 {print substr($0, length(name) + 3); exit}' "$1"
}

# release_field_epoch <release-file> <field>: a date field in seconds since
# the epoch. Dies unless it is present and written exactly as apt writes it.
release_field_epoch() {
  local release_file=$1 field=$2 value epoch
  value=$(release_field "$release_file" "$field")
  [ -n "$value" ] || die "$release_file has no $field"
  [[ "$value" =~ $RELEASE_DATE_REGEX ]] || die "$release_file: $field is not an RFC 1123 UTC date: '$value'"
  epoch=$(LC_ALL=C date -u -d "$value" +%s 2>/dev/null) || die "$release_file: $field is not a date: '$value'"
  [ "$(release_date "$epoch")" = "$value" ] || die "$release_file: $field is not a valid date: '$value'"
  printf '%s\n' "$epoch"
}

# release_days_left <release-file>: whole days until its Valid-Until (may be
# negative). Dies as release_field_epoch does.
release_days_left() {
  local valid_until
  valid_until=$(release_field_epoch "$1" Valid-Until) || return
  printf '%s\n' $(( (valid_until - $(now_epoch)) / SECONDS_PER_DAY ))
}

# check_release_window <release-file> <min-days-left>: dies unless Date and
# Valid-Until are present and well formed, Date is not in the future,
# Valid-Until is after Date by at most VALID_UNTIL_DAYS, and at least
# <min-days-left> days are left.
check_release_window() {
  local release_file=$1 min_days_left=$2 date valid_until now
  date=$(release_field_epoch "$release_file" Date) || return
  valid_until=$(release_field_epoch "$release_file" Valid-Until) || return
  now=$(now_epoch)
  [ "$date" -le $((now + RELEASE_CLOCK_SKEW_SECONDS)) ] \
    || die "$release_file: Date is in the future ($(release_date "$date"))"
  [ "$valid_until" -gt "$date" ] \
    || die "$release_file: Valid-Until is not after Date"
  [ $((valid_until - date)) -le $((VALID_UNTIL_DAYS * SECONDS_PER_DAY)) ] \
    || die "$release_file: Valid-Until is more than $VALID_UNTIL_DAYS days after Date"
  [ "$valid_until" -gt "$now" ] \
    || die "$release_file: expired at $(release_date "$valid_until") (Valid-Until)"
  [ $((valid_until - now)) -ge $((min_days_left * SECONDS_PER_DAY)) ] \
    || die "$release_file: only $(( (valid_until - now) / SECONDS_PER_DAY )) day(s) left before Valid-Until (needs $min_days_left)"
}

# check_release_fresh <release-file>: check_release_window with at least
# VALID_UNTIL_WARN_DAYS left: what a deployed or about-to-be-deployed index
# must have (recovery-sign.sh, verify-recovery-repo.sh, check-index-freshness.sh).
check_release_fresh() { check_release_window "$1" "$VALID_UNTIL_WARN_DAYS"; }

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

# ---------------------------------------------------------------------------
# The keep-alive commit on main (keepalive-commit.sh pushes it with a deploy
# key; audit-main-commits.sh accepts it, unsigned, only in exactly this shape)
# ---------------------------------------------------------------------------

# The one file it changes, a regular file holding one UTC timestamp and a
# newline (21 bytes): "2026-11-12T16:00:00Z".
readonly KEEPALIVE_FILE=keep.alive
readonly KEEPALIVE_FILE_MODE=100644
readonly KEEPALIVE_FILE_SIZE=21
readonly KEEPALIVE_TIMESTAMP_FORMAT='%Y-%m-%dT%H:%M:%SZ'
readonly KEEPALIVE_TIMESTAMP_REGEX='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$'
# Its author and committer: the identity of GITHUB_TOKEN's app, which is also
# the creator GitHub records for the commit status the workflow posts.
readonly GITHUB_ACTIONS_BOT_LOGIN='github-actions[bot]'
readonly GITHUB_ACTIONS_BOT_ID=41898282
readonly GITHUB_ACTIONS_BOT_EMAIL="$GITHUB_ACTIONS_BOT_ID+$GITHUB_ACTIONS_BOT_LOGIN@users.noreply.github.com"
readonly GITHUB_ACTIONS_BOT_IDENTITY="$GITHUB_ACTIONS_BOT_LOGIN <$GITHUB_ACTIONS_BOT_EMAIL>"
readonly KEEPALIVE_COMMIT_MESSAGE='chore(keepalive): refresh keep.alive [skip ci]'
# The commit status the workflow posts on the commit after pushing it: the
# audit's proof that the workflow, not someone else with the key, pushed it.
readonly KEEPALIVE_STATUS_CONTEXT=keepalive/pushed
readonly KEEPALIVE_STATUS_STATE=success

# is_keepalive_timestamp <text>: true if it is one timestamp in exactly that
# format, and a real date (no 31 February).
is_keepalive_timestamp() {
  [[ "$1" =~ $KEEPALIVE_TIMESTAMP_REGEX ]] || return 1
  [ "$(date -u -d "$1" +"$KEEPALIVE_TIMESTAMP_FORMAT" 2>/dev/null)" = "$1" ]
}

# is_keepalive_path_list: true if stdin, a NUL-separated path list (`git
# diff -z --name-only`), is exactly "keep.alive" and one NUL, byte for byte.
# The raw bytes are compared (as hex, since Bash strings cannot hold a NUL):
# turning the list into lines first would let a second path named
# "keep.alive<newline>" or "<newline>" read as nothing more.
is_keepalive_path_list() {
  [ "$(od -An -v -tx1 | tr -d ' \n')" = "$(printf '%s\0' "$KEEPALIVE_FILE" | od -An -v -tx1 | tr -d ' \n')" ]
}

# keepalive_commit_problems <commit>: in the current git repository, why the
# commit is not a keep-alive commit, one reason per line; nothing if it is
# one. A keep-alive commit has exactly one parent, changes exactly one path,
# keep.alive (added or modified, a regular file of one timestamp line), has
# github-actions[bot] as author and committer, and the fixed message.
keepalive_commit_problems() {
  local commit=$1 parents changed mode size content identities message
  parents=$(git rev-list --parents -n 1 "$commit" | wc -w)
  if [ "$parents" -ne 2 ]; then
    echo "has $((parents - 1)) parent(s), not 1"
    return 0
  fi
  if ! git diff-tree -r --no-commit-id --no-renames --name-only -z "$commit" | is_keepalive_path_list; then
    # For the message only: one path per line, a newline in a name shown as ?.
    changed=$(git diff-tree -r --no-commit-id --no-renames --name-only -z "$commit" | tr '\n\0' '?\n')
    echo "changes $(printf '%s' "$changed" | grep -c '') path(s), not only $KEEPALIVE_FILE: $(printf '%s' "$changed" | head -n 5 | paste -sd ' ' -)"
  else
    mode=$(git ls-tree "$commit" -- "$KEEPALIVE_FILE" | cut -d' ' -f1)
    size=$(git cat-file -s "$commit:$KEEPALIVE_FILE" 2>/dev/null || echo 0)
    content=$(git cat-file blob "$commit:$KEEPALIVE_FILE" 2>/dev/null | head -c 64 | tr -c '[:print:]\n' '?' || true)
    if [ "$mode" != "$KEEPALIVE_FILE_MODE" ]; then
      echo "$KEEPALIVE_FILE is deleted or not a regular file (mode ${mode:-none})"
    elif [ "$size" -ne "$KEEPALIVE_FILE_SIZE" ] || ! is_keepalive_timestamp "$content"; then
      echo "$KEEPALIVE_FILE is not one timestamp line ($size bytes)"
    fi
  fi
  identities=$(git show -s --format='%an <%ae>%n%cn <%ce>' "$commit")
  if [ "$identities" != "$(printf '%s\n%s' "$GITHUB_ACTIONS_BOT_IDENTITY" "$GITHUB_ACTIONS_BOT_IDENTITY")" ]; then
    echo "author or committer is not $GITHUB_ACTIONS_BOT_LOGIN: $(paste -sd '/' - <<<"$identities")"
  fi
  # The raw message, every newline kept (the x stops $() dropping them).
  message=$(git cat-file commit "$commit" | sed '1,/^$/d'; echo x)
  if [ "$message" != "$KEEPALIVE_COMMIT_MESSAGE"$'\n'x ]; then
    echo "message is not '$KEEPALIVE_COMMIT_MESSAGE'"
  fi
}

# post_keepalive_status <owner/repo> <commit> <run-url>: the keepalive/pushed
# success status on the commit, through the REST API with GH_TOKEN (a
# workflow's GITHUB_TOKEN with statuses: write).
post_keepalive_status() {
  gh api --silent -X POST "repos/$1/statuses/$2" \
    -f state="$KEEPALIVE_STATUS_STATE" -f context="$KEEPALIVE_STATUS_CONTEXT" \
    -f description="Pushed by the keep-alive workflow" -f target_url="$3"
}

# has_keepalive_status <owner/repo> <commit>: true if GitHub holds the
# keepalive/pushed success status on the commit, created by
# github-actions[bot] (by login and by account id).
has_keepalive_status() {
  gh api --paginate "repos/$1/commits/$2/statuses?per_page=100" \
    | jq -se --arg context "$KEEPALIVE_STATUS_CONTEXT" --arg state "$KEEPALIVE_STATUS_STATE" \
        --arg login "$GITHUB_ACTIONS_BOT_LOGIN" --argjson id "$GITHUB_ACTIONS_BOT_ID" '
      add // [] | any(.[]; .context == $context and .state == $state
                         and .creator.login == $login and .creator.id == $id)' >/dev/null
}
