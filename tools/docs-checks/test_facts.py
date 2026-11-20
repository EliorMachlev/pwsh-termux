#!/usr/bin/env python3
"""Test facts.py's reading of dependabot.yml lines: python3 tools/docs-checks/test_facts.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from facts import read_entry

CASES = [
    ('  - package-ecosystem: "pip"', ("package-ecosystem", "pip")),
    ("  - package-ecosystem: npm  # js", ("package-ecosystem", "npm")),
    ('    directory: "/tools/a"', ("directory", "/tools/a")),
    ("    directory: '/.clusterfuzzlite extra'", ("directory", "/.clusterfuzzlite extra")),
    ('    directory: "/a b#c"  # note', ("directory", "/a b#c")),
    ("    directory: /bare/dir # c", ("directory", "/bare/dir")),
    ("    directory: /", ("directory", "/")),
    ('      - "/tools/x y"', ("directory", "/tools/x y")),
    ("      - '/tools/z'  # c", ("directory", "/tools/z")),
    ("      - /tools/bare", ("directory", "/tools/bare")),
    # Cannot be read in full: reported, never cut short.
    ("  - directory: '/it''s'", ("directory", None)),
    ('    directory: "/a" extra', ("directory", None)),
    # Not Dependabot entries.
    ("    schedule:", None),
    ("      interval: daily", None),
]
bad = 0
for line, want in CASES:
    got = read_entry(line)
    if got != want:
        bad += 1
        print(f"FAIL {line!r}: got {got}, want {want}")
print("all passed" if not bad else f"{bad} failed")
sys.exit(1 if bad else 0)
