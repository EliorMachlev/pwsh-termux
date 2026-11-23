#!/usr/bin/env python3
"""Test site-check.py's prose rules: python3 -I .github/scripts/test_site_check.py"""
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location(
    "site_check", pathlib.Path(__file__).resolve().parent / "site-check.py"
)
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)


def prose(body: str) -> list:
    p = sc.Page()
    p.feed(f"<html><body><main>{body}</main></body></html>")
    return sc.check_prose("t.html", p)


LONG = "word " * (sc.SUMMARY_MIN_WORDS + 5)
CASES = [
    # (name, html, number of problems wanted, text the problems must hold)
    ("heading order ok", "<h1>A</h1><h2>B</h2><p>x</p>", 0, ""),
    ("heading level skipped", "<h1>A</h1><h3>B</h3>", 1, "skipped"),
    ("long page with a lead", f'<h1>A</h1><p class="lead">s</p><p>{LONG}</p>', 0, ""),
    ("long page without a lead", f"<h1>A</h1><p>{LONG}</p>", 1, "summary"),
    ("bare term", "<h1>A</h1><p>Uses apt daily.</p>", 1, "'apt'"),
    ("gloss in parentheses", "<h1>A</h1><p>Uses apt (Advanced Package Tool).</p>", 0, ""),
    ("gloss on the next line", "<h1>A</h1><p>Uses apt\n(a tool).</p>", 0, ""),
    ("titled abbr", '<h1>A</h1><p><abbr title="x">SBOM</abbr> here.</p>', 0, ""),
    ("gloss after an inline element", "<h1>A</h1><p><strong>apt</strong> (a tool).</p>", 0, ""),
    ("gloss after a link", '<h1>A</h1><p><a href="x">SBOM</a> (a list).</p>', 0, ""),
    ("term in code is exempt", "<h1>A</h1><p><code>apt</code> and <pre>DNS</pre></p>", 0, ""),
    ("only the first use is checked", "<h1>A</h1><p>apt (a tool) and apt.</p>", 0, ""),
    ("first use bare, later glossed", "<h1>A</h1><p>apt and apt (a tool).</p>", 1, "'apt'"),
    ("word part is not the term", "<h1>A</h1><p>An aptitude and IP-based.</p>", 0, ""),
    ("plural term needs a gloss", "<h1>A</h1><p>Two SBOMs here.</p>", 1, "'SBOM'"),
    ("a space before the bracket is needed", "<h1>A</h1><p>apt(a tool).</p>", 1, "'apt'"),
]

failed = 0
for name, html, want, text in CASES:
    got = prose(html)
    if len(got) != want or any(text not in g for g in got):
        failed += 1
        print(f"FAIL {name}: want {want} problem(s) with {text!r}, got {got}")
if failed:
    sys.exit(1)
print(f"all {len(CASES)} passed")
