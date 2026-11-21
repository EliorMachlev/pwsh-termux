#!/usr/bin/env python3
"""Show or apply updates to the tools pinned by hand (version and SHA-256).

Dependabot has no ecosystem for these constants, so this does the same job:
for each tool it finds the newest release that is at least COOLDOWN_DAYS old
(the two weeks docs/markDown/engineering/ci-cd/dependabot.md asks for), gets
the SHA-256 of the asset the repository downloads, and rewrites the two
constants. A release's age is its GitHub publication time; for tools-java,
which is on Maven Central, it is the Last-Modified time of that version's pom
(the metadata's lastUpdated says only when the metadata changed).

  python3 tools/pinned-tools/bump.py            # list what would change
  python3 tools/pinned-tools/bump.py --apply    # rewrite the files

Standard library only. GITHUB_TOKEN is used for the GitHub API when set. The
asset's SHA-256 comes from the project's own checksums file where one exists;
otherwise from the digest GitHub records for the asset; where there is neither
(tools-java, or a GitHub asset recorded without a digest) it is the hash of
the download, so check the release before merging. A tool that fails (a missing file, a network error) is reported and
skipped, the others are still updated, and the exit status is 1. The scripts'
tests and CI then check the new pins as usual.
"""
import datetime
import email.utils
import hashlib
import http.client
import itertools
import json
import os
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COOLDOWN_DAYS = 14
PAGE_SIZE = 30
MAVEN = "https://repo1.maven.org/maven2/org/spdx/tools-java"

# name, file, version constant, SHA-256 constant, GitHub repo (or None for
# Maven), tag prefix, asset name, checksums asset (None: GitHub's digest of
# the asset, or the hash of the download) ({v} is the version).
TOOLS = [
    ("syft", "scripts/make-sboms.sh", "SYFT_VERSION", "SYFT_SHA256", "anchore/syft", "v",
     "syft_{v}_linux_amd64.tar.gz", "syft_{v}_checksums.txt"),
    ("sbom-tool", "scripts/make-sboms.sh", "MS_SBOM_TOOL_VERSION", "MS_SBOM_TOOL_SHA256",
     "microsoft/sbom-tool", "v", "sbom-tool-linux-x64", None),
    ("tools-java", "scripts/make-sboms.sh", "SPDX_TOOLS_VERSION", "SPDX_TOOLS_SHA256", None, "",
     "tools-java-{v}-jar-with-dependencies.jar", None),
    ("jactionlint", ".github/workflows/ci.yaml", "JACTIONLINT_VERSION", "JACTIONLINT_SHA256",
     "jdx/jactionlint", "v", "jactionlint_{v}_linux_amd64.tar.gz", "jactionlint_{v}_checksums.txt"),
    ("shfmt", ".github/workflows/ci.yaml", "SHFMT_VERSION", "SHFMT_SHA256", "mvdan/sh", "v",
     "shfmt_v{v}_linux_amd64", None),
    ("lychee", ".github/workflows/docs-checks.yaml", "LYCHEE_VERSION", "LYCHEE_SHA256",
     "lycheeverse/lychee", "lychee-v", "lychee-x86_64-unknown-linux-gnu.tar.gz",
     "lychee-x86_64-unknown-linux-gnu.tar.gz.sha256"),
]


def get(url, method="GET"):
    request = urllib.request.Request(url, method=method, headers={"User-Agent": "pwsh-termux-bump"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read() if method == "GET" else response.headers


def version_key(version):
    return [int(part) for part in re.findall(r"\d+", version)]


def old_enough(when):
    return datetime.datetime.now(datetime.UTC) - when >= datetime.timedelta(days=COOLDOWN_DAYS)


def github_latest(repo, prefix):
    """(version, tag, {asset name: sha256 digest}) of the newest stable release
    past the cooldown, or None. Follows the pages of the releases list until
    they run out."""
    found = []
    for page in itertools.count(1):
        releases = json.loads(get(f"https://api.github.com/repos/{repo}/releases?per_page={PAGE_SIZE}&page={page}"))
        for release in releases:
            tag = release["tag_name"]
            if release["draft"] or release["prerelease"] or not tag.startswith(prefix):
                continue
            version = tag[len(prefix):]
            published = datetime.datetime.fromisoformat(release["published_at"])
            if re.fullmatch(r"\d+(\.\d+)*", version) and old_enough(published):
                digests = {a["name"]: a["digest"].removeprefix("sha256:") for a in release["assets"] if a.get("digest")}
                found.append((version_key(version), version, tag, digests))
        if len(releases) < PAGE_SIZE:
            break
    if not found:
        return None
    _, version, tag, digests = max(found, key=lambda item: item[0])
    return version, tag, digests


def maven_latest():
    """The newest version whose pom is past the cooldown, or None."""
    meta = ET.fromstring(get(f"{MAVEN}/maven-metadata.xml"))
    versions = [v.text for v in meta.findall("versioning/versions/version") if re.fullmatch(r"\d+(\.\d+)*", v.text)]
    for version in sorted(versions, key=version_key, reverse=True):
        modified = get(f"{MAVEN}/{version}/tools-java-{version}.pom", "HEAD")["Last-Modified"]
        if old_enough(email.utils.parsedate_to_datetime(modified)):
            return version
    return None


def sha256_from(checksums, asset):
    for line in checksums.decode().splitlines():
        parts = line.split()
        if len(parts) >= 1 and (len(parts) == 1 or parts[-1].lstrip("*") == asset):
            return parts[0]
    raise RuntimeError(f"no checksum for {asset}")


def pinned(text, name):
    match = re.search(rf"^\s*(?:readonly )?{name}(?:=|:\s*\"?)([^\s\"]+)", text, re.MULTILINE)
    if not match:
        raise RuntimeError(f"{name} not found")
    return match.group(1)


def replace(text, name, value):
    new, count = re.subn(rf"(^\s*(?:readonly )?{name}(?:=|:\s*\"?))[^\s\"]+", lambda m: m.group(1) + value, text, count=1, flags=re.MULTILINE)
    if not count:
        raise RuntimeError(f"{name} not found")
    return new


def update(text, tool):
    """(version, digest, new text) for one tool; version None when there is nothing to do."""
    name, _, vname, sname, repo, prefix, asset, checksums = tool
    current = pinned(text, vname)
    digests = {}
    if repo:
        latest = github_latest(repo, prefix)
        version, tag, digests = latest or (None, None, {})
        base = f"https://github.com/{repo}/releases/download/{tag}"
    else:
        version = maven_latest()
        base = f"{MAVEN}/{version}"
    if version is None:
        print(f"{name}: nothing past the {COOLDOWN_DAYS}-day cooldown")
        return None
    if version_key(version) <= version_key(current):
        print(f"{name}: {current} is current")
        return None
    file_name = asset.format(v=version)
    if checksums:
        digest = sha256_from(get(f"{base}/{checksums.format(v=version)}"), file_name)
    else:
        digest = digests.get(file_name) or hashlib.sha256(get(f"{base}/{file_name}")).hexdigest()
    print(f"{name}: {current} -> {version}  sha256 {digest}")
    return replace(replace(text, vname, version), sname, digest)


def main():
    apply = "--apply" in sys.argv[1:]
    texts = {}
    changed = failed = 0
    for tool in TOOLS:
        path = tool[1]
        try:
            if path not in texts:
                texts[path] = (ROOT / path).read_text()
            new = update(texts[path], tool)
        except (RuntimeError, http.client.HTTPException, OSError, ValueError, KeyError, ET.ParseError) as error:
            print(f"{tool[0]}: FAILED, skipped: {error}", file=sys.stderr)
            failed += 1
            continue
        if new is not None:
            texts[path] = new
            changed += 1
    if apply:
        for path, text in texts.items():
            (ROOT / path).write_text(text)
    print(f"{changed} tool(s) {'updated' if apply else 'could be updated (--apply)'}, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
