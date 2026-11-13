#!/usr/bin/env bash
# Tests of validate-site.sh, with the real vnu.jar on small fixture sites:
# a valid page passes (its CSP 'self' stylesheet included), and an error, a
# warning, an info message, a bad stylesheet or a bad SVG each fail, as do
# an empty folder and a missing jar. The real site is checked by site.yaml
# itself. Offline (the pages come from a local server); touches nothing
# outside a temporary folder.
#
# Usage: test-validate-site.sh <vnu.jar>
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

VNU_JAR=${1:?vnu.jar}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
VALIDATE=$SCRIPTS_DIR/validate-site.sh

fails=0
pass() { printf 'ok    %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
# expect <accept|refuse> <description> <command...>: as in test-keys.sh.
expect() {
  local want=$1 what=$2; shift 2
  local got=refuse
  if "$@" >"$T/out.log" 2>&1; then got=accept; fi
  if [ "$got" = "$want" ]; then
    pass "$what"
    if [ "$got" = refuse ]; then printf '        %s\n' "$(grep -E 'ERROR' "$T/out.log" | tail -1)"; fi
  else
    fail "$what ($got, expected $want)"
    cat "$T/out.log"
  fi
}
# expect_message <description> <fixed-string>: the last run printed it.
expect_message() {
  if grep -qF -- "$2" "$T/out.log"; then pass "$1"; else fail "$1: no '$2'"; cat "$T/out.log"; fi
}

# page <dir> <body-html>: a valid page around the body, under the site's own
# CSP, with the site's stylesheet and icon (both in the folder).
page() {
  mkdir -p "$1"
  cat > "$1/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'">
<title>Fixture</title>
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/style.css">
</head>
<body>
$2
</body>
</html>
EOF
  printf 'p {\n  color: #123;\n}\n' > "$1/style.css"
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><rect width="1" height="1"/></svg>\n' > "$1/icon.svg"
}

echo "== validate-site.sh"
page "$T/good" '<main><h1>Fixture</h1><p>Text.</p></main>'
expect accept "a valid page, stylesheet and SVG (CSP 'self' over HTTP)" bash "$VALIDATE" "$VNU_JAR" "$T/good"

page "$T/error" '<main><h1>Fixture</h1><pre aria-label="Command"><code>ls</code></pre></main>'
expect refuse "an error (aria-label on a pre without a role)" bash "$VALIDATE" "$VNU_JAR" "$T/error"
expect_message "  the error is printed" 'error: The “aria-label” attribute must not be specified on any “pre” element'

page "$T/warning" '<main><h1>Fixture</h1><section><p>Text.</p></section></main>'
expect refuse "a warning alone (a section without a heading)" bash "$VALIDATE" "$VNU_JAR" "$T/warning"
expect_message "  the warning is printed" 'warning: Section lacks heading.'

page "$T/info" '<main><h1>Fixture</h1><p>One<br/>two</p></main>'
expect refuse "an info message alone (a trailing slash on a void element)" bash "$VALIDATE" "$VNU_JAR" "$T/info"
expect_message "  the info message is printed" 'info: Trailing slash on void elements has no effect'

page "$T/css" '<main><h1>Fixture</h1></main>'
printf 'p {\n  colr: #123;\n}\n' > "$T/css/style.css"
expect refuse "a stylesheet with an unknown property" bash "$VALIDATE" "$VNU_JAR" "$T/css"
expect_message "  the stylesheet is named" 'style.css'

page "$T/svg" '<main><h1>Fixture</h1></main>'
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><p>not SVG</p></svg>\n' > "$T/svg/icon.svg"
expect refuse "an SVG with an element SVG does not have" bash "$VALIDATE" "$VNU_JAR" "$T/svg"
expect_message "  the SVG is named" 'icon.svg'

mkdir "$T/empty"
expect refuse "a folder with nothing to check" bash "$VALIDATE" "$VNU_JAR" "$T/empty"
expect refuse "a missing vnu.jar" bash "$VALIDATE" "$T/no-such.jar" "$T/good"

echo
if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
