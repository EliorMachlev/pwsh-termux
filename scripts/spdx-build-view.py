#!/usr/bin/env python3
"""Write the packaging view of a .deb as an SPDX 2.3 document.

Usage: spdx-build-view.py <package.deb> <package.build.json> <out.json>

What the build used, as the build recorded it (no scan). For pwsh and
pwsh-preview (build-deb.sh): the .deb, the official tarball it was made from
and that tarball's SHA-256, the tool that patched it, and the packages it
depends on. For pwsh-termux-keyring (build-keyring.sh): the .deb and the
committed keyring file it was made from, with that file's SHA-256. Syft and
the Microsoft SBOM tool write the other views, from the package's files.

A build record that is not what those scripts write (not a JSON object, a
missing or empty field, a checksum that is not a SHA-256) is refused with a
one-line error and exit status 1, never a traceback.
tests/fuzz/test_spdx_build_view.py checks this file with Hypothesis.
"""

import hashlib
import json
import re
import subprocess
import sys
import uuid
from datetime import UTC, datetime
from typing import Any
from urllib.parse import quote

PROJECT_URL = "https://github.com/EliorMachlev/pwsh-termux"
SPDX_NAMESPACE_BASE = f"{PROJECT_URL}/spdx"
CREATOR_TOOL = "Tool: pwsh-termux-spdx-build-view"
NOASSERTION = "NOASSERTION"

DOCUMENT_ID = "SPDXRef-DOCUMENT"
DEB_ID = "SPDXRef-Package-deb"
UPSTREAM_ID = "SPDXRef-Package-upstream"
PATCHELF_ID = "SPDXRef-Package-patchelf"
KEYRING_SOURCE_ID = "SPDXRef-Package-keyring-source"
DEPENDENCY_ID_PREFIX = "SPDXRef-Package-dep-"

MICROSOFT_SUPPLIER = "Organization: Microsoft Corporation"
PATCHELF_URL = "https://github.com/NixOS/patchelf"

# The characters an SPDX 2.3 identifier may have after "SPDXRef-".
SPDX_ID_UNSAFE = re.compile(r"[^A-Za-z0-9.-]")
SHA256_HEX = re.compile(r"[0-9a-f]{64}")
# A package name at the start of one alternative of a Depends field: it ends
# at a version constraint "(", an architecture qualifier ":", an architecture
# list "[" or a build profile "<", with or without a space before them.
DEPENDENCY_NAME = re.compile(r"[^\s(:\[<]+")

UPSTREAM_FIELDS = (
    "package",
    "version",
    "upstream_tag",
    "upstream_url",
    "upstream_sha256",
    "patchelf_version",
)
KEYRING_FIELDS = ("package", "version", "source_file", "source_sha256")

Package = dict[str, Any]
Relationship = dict[str, str]


class BuildRecordError(ValueError):
    """The build record is not one build-deb.sh or build-keyring.sh writes."""


def deb_field(deb: str, field: str) -> str:
    """One control field of the .deb, as dpkg-deb -f prints it."""
    return subprocess.check_output(["dpkg-deb", "-f", deb, field], text=True).strip()


def file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def check_build_record(build: Any) -> dict[str, str]:
    """The record's fields, each checked to be a non-empty string.

    An upstream_tag means a pwsh record; otherwise a keyring one. Checksums
    must be SHA-256 in hex (stored in lowercase, as SPDX writes them).
    """
    if not isinstance(build, dict):
        raise BuildRecordError(f"not a JSON object but {type(build).__name__}")
    fields = UPSTREAM_FIELDS if "upstream_tag" in build else KEYRING_FIELDS
    checked = {}
    for field in fields:
        value = build.get(field)
        if not isinstance(value, str) or not value.strip():
            raise BuildRecordError(f"{field} is missing or not a non-empty string")
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise BuildRecordError(f"{field} is not valid Unicode") from None
        checked[field] = value
    for field in ("upstream_sha256", "source_sha256"):
        if field in checked:
            sha = checked[field].lower()
            if not SHA256_HEX.fullmatch(sha):
                raise BuildRecordError(f"{field} is not a SHA-256 in hex")
            checked[field] = sha
    if "upstream_tag" in checked and not checked["upstream_tag"].removeprefix("v"):
        raise BuildRecordError("upstream_tag has no version after its v")
    return checked


def dependency_names(depends: str) -> list[str]:
    """Package names from a Depends field, without version constraints.

    Every alternative of an "a | b" group counts, and each name once.
    """
    names: dict[str, None] = {}
    for group in depends.split(","):
        for alternative in group.split("|"):
            m = DEPENDENCY_NAME.match(alternative.strip())
            if m:
                names[m.group()] = None
    return list(names)


def spdx_ids(prefix: str, names: list[str]) -> list[str]:
    """One SPDX identifier per name, each unique.

    Characters SPDX does not allow (Debian names may have "+") become "-";
    a name that then clashes with an earlier one gets "-2", "-3", ...
    """
    ids: list[str] = []
    taken: set[str] = set()
    for name in names:
        base = prefix + SPDX_ID_UNSAFE.sub("-", name)
        sid, n = base, 1
        while sid in taken:
            n += 1
            sid = f"{base}-{n}"
        taken.add(sid)
        ids.append(sid)
    return ids


def purl_part(value: str) -> str:
    """A purl name, version or qualifier value, percent-encoded."""
    return quote(value, safe="")


def purl_ref(locator: str) -> list[dict[str, str]]:
    return [
        {
            "referenceCategory": "PACKAGE-MANAGER",
            "referenceType": "purl",
            "referenceLocator": locator,
        }
    ]


def relationship(element: str, kind: str, related: str) -> Relationship:
    return {
        "spdxElementId": element,
        "relationshipType": kind,
        "relatedSpdxElement": related,
    }


def pkg(
    spdx_id: str,
    name: str,
    version: str,
    download: str,
    sha: str | None = None,
    **extra: Any,
) -> Package:
    p = {
        "SPDXID": spdx_id,
        "name": name,
        "versionInfo": version,
        "downloadLocation": download,
        "filesAnalyzed": False,
        "licenseConcluded": NOASSERTION,
        "licenseDeclared": NOASSERTION,
        "copyrightText": NOASSERTION,
    }
    if sha:
        p["checksums"] = [{"algorithm": "SHA256", "checksumValue": sha}]
    p.update(extra)
    return p


def upstream_packages(
    build: dict[str, str],
) -> tuple[list[Package], list[Relationship]]:
    """pwsh, pwsh-preview: Microsoft's tarball, patched with patchelf."""
    tag = build["upstream_tag"]
    patchelf = build["patchelf_version"]
    packages = [
        pkg(
            UPSTREAM_ID,
            "PowerShell",
            tag.removeprefix("v"),
            build["upstream_url"],
            build["upstream_sha256"],
            licenseDeclared="MIT",
            supplier=MICROSOFT_SUPPLIER,
            externalRefs=purl_ref(f"pkg:github/PowerShell/PowerShell@{purl_part(tag)}"),
        ),
        pkg(
            PATCHELF_ID,
            "patchelf",
            patchelf,
            PATCHELF_URL,
            externalRefs=purl_ref(f"pkg:generic/patchelf@{purl_part(patchelf)}"),
        ),
    ]
    rels = [
        relationship(DEB_ID, "GENERATED_FROM", UPSTREAM_ID),
        relationship(PATCHELF_ID, "BUILD_TOOL_OF", DEB_ID),
    ]
    return packages, rels


def keyring_source_packages(
    build: dict[str, str],
) -> tuple[list[Package], list[Relationship]]:
    """pwsh-termux-keyring: the public keyring committed to this repository."""
    packages = [
        pkg(
            KEYRING_SOURCE_ID,
            build["source_file"],
            NOASSERTION,
            f"git+{PROJECT_URL}",
            build["source_sha256"],
            licenseDeclared="MIT",
            supplier=NOASSERTION,
            comment="The public OpenPGP keys the package installs, "
            "as committed to the repository.",
        ),
    ]
    return packages, [relationship(DEB_ID, "GENERATED_FROM", KEYRING_SOURCE_ID)]


def dependency_packages(deps: list[str]) -> tuple[list[Package], list[Relationship]]:
    packages, rels = [], []
    for d, sid in zip(deps, spdx_ids(DEPENDENCY_ID_PREFIX, deps), strict=True):
        packages.append(
            pkg(
                sid,
                d,
                NOASSERTION,
                NOASSERTION,
                comment="Termux package this one depends on at run time; "
                "not part of it.",
            )
        )
        rels.append(relationship(DEB_ID, "DEPENDS_ON", sid))
    return packages, rels


def build_document(deb: str, record: Any) -> dict[str, Any]:
    build = check_build_record(record)
    deps = dependency_names(deb_field(deb, "Depends"))
    arch = deb_field(deb, "Architecture")
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    name, version = build["package"], build["version"]

    purl = (
        f"pkg:deb/termux/{purl_part(name)}@{purl_part(version)}?arch={purl_part(arch)}"
    )
    deb_pkg = pkg(
        DEB_ID,
        name,
        version,
        NOASSERTION,
        file_sha256(deb),
        licenseDeclared="MIT",
        supplier=NOASSERTION,
        externalRefs=purl_ref(purl),
    )
    packages = [deb_pkg]
    rels = [relationship(DOCUMENT_ID, "DESCRIBES", DEB_ID)]

    sources = (
        upstream_packages(build)
        if "upstream_tag" in build
        else keyring_source_packages(build)
    )
    for more_packages, more_rels in (sources, dependency_packages(deps)):
        packages += more_packages
        rels += more_rels

    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": DOCUMENT_ID,
        "name": f"{name}_{version}_{arch} (packaging view)",
        "documentNamespace": f"{SPDX_NAMESPACE_BASE}/{purl_part(name)}-"
        f"{purl_part(version)}-{uuid.uuid4()}",
        "creationInfo": {"created": now, "creators": [CREATOR_TOOL]},
        "packages": packages,
        "relationships": rels,
    }


def main(argv: list[str] | None = None) -> None:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3:
        sys.exit("usage: spdx-build-view.py <package.deb> <build.json> <out.json>")
    deb, record, out = args
    try:
        with open(record, encoding="utf-8") as f:
            build = json.load(f)
        doc = build_document(deb, build)
    except (ValueError, RecursionError) as e:
        # Not UTF-8, not JSON, nested too deep, or not a build record.
        sys.exit(f"spdx-build-view.py: {record}: {e}")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2)


if __name__ == "__main__":
    main()
