#!/usr/bin/env bash
# Validate the website with the W3C Nu Html Checker (vnu): every page, every
# stylesheet and every SVG at the top of a folder (docs/, the assembled site
# in the repository folder, or art/brand). Any message fails: an error, a
# warning, or an info message. Nothing is filtered.
#
# Usage: validate-site.sh <vnu.jar> <site-dir>
#
# The pages are checked as a browser gets them: served over HTTP from a local
# server (127.0.0.1, a free port), so their Content-Security-Policy's 'self'
# is the site's own origin. Checked as file: URLs instead, vnu reports every
# local stylesheet and icon as blocked by the CSP, which a served page is
# not. vnu refuses to fetch from a loopback address unless told it may
# (nu.validator.servlet.allow-forbidden-hosts): that guards a public checker
# service against reaching its own host, and changes nothing in what it
# reports. Stylesheets and SVGs have no CSP and are checked as files.
#
# Needs java (17 or later), python3 and curl.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VNU_JAR=${1:?vnu.jar}
SITE_DIR=${2:?site directory}

readonly LOOPBACK=127.0.0.1
readonly SERVER_WAIT_SECONDS=20

# Removed on exit; the server stopped.
WORK_DIR=
SERVER_PID=

cleanup() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WORK_DIR"
}

# free_port: a TCP port nothing listens on now.
free_port() {
  python3 -I -c 'import socket; s = socket.socket(); s.bind(("'"$LOOPBACK"'", 0)); print(s.getsockname()[1])'
}

# serve <dir> <port>: a static server for the folder, until exit.
serve() {
  python3 -I -m http.server "$2" --bind "$LOOPBACK" --directory "$1" > "$WORK_DIR/server.log" 2>&1 &
  SERVER_PID=$!
  curl -fs -o /dev/null --retry "$SERVER_WAIT_SECONDS" --retry-delay 1 --retry-connrefused \
    "http://$LOOPBACK:$2/" || { cat "$WORK_DIR/server.log" >&2; die "the local server did not start"; }
}

main() {
  local port page pages=() urls=() others=() status=0 report
  [ -f "$VNU_JAR" ] || die "$VNU_JAR not found"
  [ -d "$SITE_DIR" ] || die "$SITE_DIR is not a folder"
  shopt -s nullglob
  pages=("$SITE_DIR"/*.html)
  others=("$SITE_DIR"/*.css "$SITE_DIR"/*.svg)
  [ "$((${#pages[@]} + ${#others[@]}))" -gt 0 ] || die "nothing to check (*.html, *.css, *.svg) in $SITE_DIR"

  WORK_DIR=$(mktemp -d)
  trap cleanup EXIT
  if [ "${#pages[@]}" -gt 0 ]; then
    port=$(free_port)
    serve "$SITE_DIR" "$port"
    for page in "${pages[@]}"; do
      urls+=("http://$LOOPBACK:$port/$(basename "$page")")
    done
  fi

  log "checking ${#pages[@]} page(s) and ${#others[@]} stylesheet(s)/SVG(s) in $SITE_DIR"
  java -Dnu.validator.servlet.allow-forbidden-hosts=true -jar "$VNU_JAR" \
    --Werror --also-check-css --also-check-svg --format gnu \
    "${urls[@]}" "${others[@]}" > "$WORK_DIR/report" 2>&1 || status=$?
  # --Werror: a warning or an info message fails like an error does. Any
  # output fails too, so no message can pass whatever its level.
  report=$WORK_DIR/report
  if [ "$status" -ne 0 ] || [ -s "$report" ]; then
    cat "$report" >&2
    die "vnu reported $(wc -l < "$report") line(s) for $SITE_DIR (exit $status)"
  fi
  log "no messages: $SITE_DIR is valid"
}

main
