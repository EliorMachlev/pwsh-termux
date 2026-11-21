#!/usr/bin/env python3
"""Test bump.py offline, with a fake GitHub API: python3 tools/pinned-tools/test_bump.py"""
import datetime
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bump

NOW = datetime.datetime.now(datetime.UTC)
OLD = (NOW - datetime.timedelta(days=60)).isoformat()
NEW = (NOW - datetime.timedelta(days=1)).isoformat()


def release(version, published=OLD, prerelease=False, digest="sha256:aa"):
    return {
        "tag_name": f"v{version}",
        "draft": False,
        "prerelease": prerelease,
        "published_at": published,
        "assets": [{"name": "tool", "digest": digest}, {"name": "nodigest"}],
    }


def fake_api(pages):
    """get() that serves `pages` (lists of releases) as GitHub's pages, and counts requests."""
    calls = []

    def get(url, method="GET"):
        calls.append(url)
        page = int(url.rsplit("page=", 1)[1])
        return json.dumps(pages[page - 1] if page <= len(pages) else []).encode()

    return get, calls


bad = 0


def check(what, got, want):
    global bad
    if got != want:
        bad += 1
        print(f"FAIL {what}: got {got!r}, want {want!r}")
    else:
        print(f"ok   {what}")


full = bump.PAGE_SIZE
filler = [release(f"9.{i}", published=NEW) for i in range(full)]  # in the cooldown

# An eligible release on page 11, after ten full pages that are all in the cooldown.
bump.get, calls = fake_api([filler] * 10 + [[release("1.2.3")]])
check("a release on page 11 is found", bump.github_latest("o/r", "v"), ("1.2.3", "v1.2.3", {"tool": "aa"}))
check("pages are followed until a short one", len(calls), 11)

# The highest eligible version wins across pages; prereleases and cooldown are skipped.
pages = [
    [release(f"2.{i}", published=NEW) for i in range(full)],
    [release("1.5.0"), release("1.9.0", prerelease=True)] + [release(f"0.{i}") for i in range(full - 2)],
    [release("1.10.0")],
]
bump.get, _ = fake_api(pages)
check("highest eligible across pages", bump.github_latest("o/r", "v")[0], "1.10.0")

bump.get, _ = fake_api([filler])
check("nothing eligible", bump.github_latest("o/r", "v"), None)

# An asset without a digest has none recorded (bump.py then hashes the download).
bump.get, _ = fake_api([[release("1.0.0")]])
check("an asset without a digest is absent", "nodigest" in bump.github_latest("o/r", "v")[2], False)

print("all passed" if not bad else f"{bad} failed")
sys.exit(1 if bad else 0)
