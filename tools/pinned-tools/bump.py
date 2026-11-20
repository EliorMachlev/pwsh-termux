#!/usr/bin/env python3
"""Show or apply updates to the tools pinned by hand (version and SHA-256).

Dependabot has no ecosystem for these constants, so this does the same job:
for each tool it finds the newest release that is at least COOLDOWN_DAYS old
(the two weeks docs/markDown/engineering/ci-cd/dependabot.md asks for), reads or computes the SHA-256 of the asset the
repository downloads, and rewrites the two constants.

  python3 tools/pinned-tools/bump.py            # list what would change
  python3 tools/pinned-tools/bump.py --apply    # rewrite the files

Standard library only. GITHUB_TOKEN is used for the GitHub API when set. The
asset's SHA-256 comes from the project's own checksums file where one exists;
for the two that publish none (Microsoft's SBOM tool, tools-java) it is the
hash of the download, so check the release before merging. The scripts' tests
and CI then check the new pins as usual.
"""
import datetime
import hashlib
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COOLDOWN_DAYS = 14
MAVEN = "https://repo1.maven.org/maven2/org/spdx/tools-java"

# name, file, version constant, SHA-256 constant, GitHub repo (or None for
# Maven), tag prefix, asset name, checksums asset (None: hash the download)
# ({v} is the version).
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
     "shfmt_v{v}_linux_amd64", "sha256sums.txt"),
    ("lychee", ".github/workflows/docs-checks.yaml", "LYCHEE_VERSION", "LYCHEE_SHA256",
     "lycheeverse/lychee", "lychee-v", "lychee-x86_64-unknown-linux-gnu.tar.gz",
     "lychee-x86_64-unknown-linux-gnu.tar.gz.sha256"),
]


def get(url):
    request = urllib.request.Request(url, headers={"User-Agent": "pwsh-termux-bump"})
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def version_key(version):
    return [int(part) for part in re.findall(r"\d+", version)]


def old_enough(when):
    return datetime.datetime.now(datetime.UTC) - when >= datetime.timedelta(days=COOLDOWN_DAYS)


def github_latest(repo, prefix):
    """(version, tag) of the newest stable release past the cooldown, or None."""
    releases = json.loads(get(f"https://api.github.com/repos/{repo}/releases?per_page=30"))
    found = []
    for release in releases:
        tag = release["tag_name"]
        if release["draft"] or release["prerelease"] or not tag.startswith(prefix):
            continue
        version = tag[len(prefix):]
        published = datetime.datetime.fromisoformat(release["published_at"])
        if re.fullmatch(r"\d+(\.\d+)*", version) and old_enough(published):
            found.append((version_key(version), version, tag))
    if not found:
        return None
    _, version, tag = max(found)
    return version, tag


def maven_latest():
    meta = ET.fromstring(get(f"{MAVEN}/maven-metadata.xml"))
    stamp = datetime.datetime.strptime(meta.findtext("versioning/lastUpdated"), "%Y%m%d%H%M%S")
    if not old_enough(stamp.replace(tzinfo=datetime.UTC)):
        return None
    versions = [v.text for v in meta.findall("versioning/versions/version") if re.fullmatch(r"\d+(\.\d+)*", v.text)]
    return max(versions, key=version_key)


def sha256_from(checksums, asset):
    for line in checksums.decode().splitlines():
        parts = line.split()
        if len(parts) >= 1 and (len(parts) == 1 or parts[-1].lstrip("*") == asset):
            return parts[0]
    sys.exit(f"no checksum for {asset}")


def pinned(text, name):
    match = re.search(rf"^\s*(?:readonly )?{name}(?:=|:\s*\"?)([^\s\"]+)", text, re.MULTILINE)
    if not match:
        sys.exit(f"{name} not found")
    return match.group(1)


def replace(text, name, value):
    return re.sub(rf"(^\s*(?:readonly )?{name}(?:=|:\s*\"?))[^\s\"]+", lambda m: m.group(1) + value, text, count=1, flags=re.MULTILINE)


def main():
    apply = "--apply" in sys.argv[1:]
    texts = {}
    changed = 0
    for name, path, vname, sname, repo, prefix, asset, checksums in TOOLS:
        text = texts.setdefault(path, (ROOT / path).read_text())
        current = pinned(text, vname)
        if repo:
            latest = github_latest(repo, prefix)
            version, tag = latest or (None, None)
            base = f"https://github.com/{repo}/releases/download/{tag}"
        else:
            version = maven_latest()
            base = f"{MAVEN}/{version}"
        if version is None:
            print(f"{name}: nothing past the {COOLDOWN_DAYS}-day cooldown")
            continue
        if version_key(version) <= version_key(current):
            print(f"{name}: {current} is current")
            continue
        file_name = asset.format(v=version)
        if checksums:
            digest = sha256_from(get(f"{base}/{checksums.format(v=version)}"), file_name)
        else:
            digest = hashlib.sha256(get(f"{base}/{file_name}")).hexdigest()
        print(f"{name}: {current} -> {version}  sha256 {digest}")
        texts[path] = replace(replace(text, vname, version), sname, digest)
        changed += 1
    if apply:
        for path, text in texts.items():
            (ROOT / path).write_text(text)
    print(f"{changed} tool(s) {'updated' if apply else 'could be updated (--apply)'}")


if __name__ == "__main__":
    main()
