#!/usr/bin/env python3
"""Test facts.py's reading of dependabot.yml: python3 tools/docs-checks/test_facts.py"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from facts import dependabot_entries

YML = """
updates:
  - package-ecosystem: "pip"
    directory: '/.clusterfuzzlite extra'
  - package-ecosystem: npm  # js
    directory: /.clusterfuzzlite#extra
  - package-ecosystem: docker
    directories:
      - /bare dir # comment
      - "/a b#c"
      - '/it''s'
      - /x#y z
"""
WANT = [
    ("package-ecosystem", "pip"),
    ("directory", "/.clusterfuzzlite extra"),
    ("package-ecosystem", "npm"),
    ("directory", "/.clusterfuzzlite#extra"),
    ("package-ecosystem", "docker"),
    ("directory", "/bare dir"),
    ("directory", "/a b#c"),
    ("directory", "/it's"),
    ("directory", "/x#y z"),
]
got = dependabot_entries(YML)
if got != WANT:
    print(f"FAIL\n got  {got}\n want {WANT}")
    sys.exit(1)
print("all passed")
