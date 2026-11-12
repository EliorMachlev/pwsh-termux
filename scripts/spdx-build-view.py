#!/usr/bin/env python3
"""Write the packaging view of a .deb as an SPDX 2.3 document.

Usage: spdx-build-view.py <package.deb> <package.build.json> <out.json>

What the build used, as the build recorded it (no scan). For pwsh and
pwsh-preview (build-deb.sh): the .deb, the official tarball it was made from
and that tarball's SHA-256, the tool that patched it, and the packages it
depends on. For pwsh-termux-keyring (build-keyring.sh): the .deb and the
committed keyring file it was made from, with that file's SHA-256. Syft and
the Microsoft SBOM tool write the other views, from the package's files.
"""
import hashlib
import json
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from typing import Any

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

Package = dict[str, Any]
Relationship = dict[str, str]


def deb_field(deb: str, field: str) -> str:
    """One control field of the .deb, as dpkg-deb -f prints it."""
    return subprocess.check_output(["dpkg-deb", "-f", deb, field], text=True).strip()


def file_sha256(path: str) -> str:
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def dependency_names(depends: str) -> list[str]:
    """Package names from a Depends field, without version constraints."""
    return [d.strip().split()[0] for d in depends.split(",") if d.strip()]


def purl_ref(locator: str) -> list[dict[str, str]]:
    return [{"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
             "referenceLocator": locator}]


def relationship(element: str, kind: str, related: str) -> Relationship:
    return {"spdxElementId": element, "relationshipType": kind, "relatedSpdxElement": related}


def pkg(spdx_id: str, name: str, version: str, download: str, sha: str | None = None,
        **extra: Any) -> Package:
    p = {"SPDXID": spdx_id, "name": name, "versionInfo": version,
         "downloadLocation": download, "filesAnalyzed": False,
         "licenseConcluded": NOASSERTION, "licenseDeclared": NOASSERTION,
         "copyrightText": NOASSERTION}
    if sha:
        p["checksums"] = [{"algorithm": "SHA256", "checksumValue": sha}]
    p.update(extra)
    return p


def upstream_packages(build: dict[str, Any]) -> tuple[list[Package], list[Relationship]]:
    """pwsh, pwsh-preview: Microsoft's tarball, patched with patchelf."""
    upstream_ver = build["upstream_tag"].lstrip("v")
    packages = [
        pkg(UPSTREAM_ID, "PowerShell", upstream_ver, build["upstream_url"],
            build["upstream_sha256"], licenseDeclared="MIT", supplier=MICROSOFT_SUPPLIER,
            externalRefs=purl_ref(f"pkg:github/PowerShell/PowerShell@{build['upstream_tag']}")),
        pkg(PATCHELF_ID, "patchelf", build["patchelf_version"], PATCHELF_URL,
            externalRefs=purl_ref(f"pkg:generic/patchelf@{build['patchelf_version']}")),
    ]
    rels = [
        relationship(DEB_ID, "GENERATED_FROM", UPSTREAM_ID),
        relationship(PATCHELF_ID, "BUILD_TOOL_OF", DEB_ID),
    ]
    return packages, rels


def keyring_source_packages(build: dict[str, Any]) -> tuple[list[Package], list[Relationship]]:
    """pwsh-termux-keyring: the public keyring committed to this repository."""
    packages = [
        pkg(KEYRING_SOURCE_ID, build["source_file"], NOASSERTION,
            f"git+{PROJECT_URL}", build["source_sha256"],
            licenseDeclared="MIT", supplier=NOASSERTION,
            comment="The public OpenPGP keys the package installs, as committed to the repository."),
    ]
    return packages, [relationship(DEB_ID, "GENERATED_FROM", KEYRING_SOURCE_ID)]


def dependency_packages(deps: list[str]) -> tuple[list[Package], list[Relationship]]:
    packages, rels = [], []
    for d in deps:
        sid = DEPENDENCY_ID_PREFIX + d.replace("_", "-")
        packages.append(pkg(sid, d, NOASSERTION, NOASSERTION,
                            comment="Termux package this one depends on at run time; not part of it."))
        rels.append(relationship(DEB_ID, "DEPENDS_ON", sid))
    return packages, rels


def build_document(deb: str, build: dict[str, Any]) -> dict[str, Any]:
    deps = dependency_names(deb_field(deb, "Depends"))
    arch = deb_field(deb, "Architecture")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    deb_pkg = pkg(DEB_ID, build["package"], build["version"], NOASSERTION, file_sha256(deb),
                  licenseDeclared="MIT", supplier=NOASSERTION,
                  externalRefs=purl_ref(f"pkg:deb/termux/{build['package']}@{build['version']}?arch={arch}"))
    packages = [deb_pkg]
    rels = [relationship(DOCUMENT_ID, "DESCRIBES", DEB_ID)]

    sources = upstream_packages(build) if "upstream_tag" in build else keyring_source_packages(build)
    for more_packages, more_rels in (sources, dependency_packages(deps)):
        packages += more_packages
        rels += more_rels

    return {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": DOCUMENT_ID,
        "name": f"{build['package']}_{build['version']}_{arch} (packaging view)",
        "documentNamespace": f"{SPDX_NAMESPACE_BASE}/{build['package']}-{build['version']}-{uuid.uuid4()}",
        "creationInfo": {"created": now, "creators": [CREATOR_TOOL]},
        "packages": packages, "relationships": rels,
    }


def main() -> None:
    deb, record, out = sys.argv[1:4]
    with open(record) as f:
        build = json.load(f)
    doc = build_document(deb, build)
    with open(out, "w") as f:
        json.dump(doc, f, indent=2)


if __name__ == "__main__":
    main()
