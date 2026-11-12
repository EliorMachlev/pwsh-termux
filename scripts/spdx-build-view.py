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

deb, record, out = sys.argv[1:4]
b = json.load(open(record))
deb_sha = hashlib.sha256(open(deb, "rb").read()).hexdigest()
depends = subprocess.check_output(["dpkg-deb", "-f", deb, "Depends"], text=True).strip()
deps = [d.strip().split()[0] for d in depends.split(",") if d.strip()]
arch = subprocess.check_output(["dpkg-deb", "-f", deb, "Architecture"], text=True).strip()
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def pkg(spdx_id, name, version, download, sha=None, **extra):
    p = {"SPDXID": spdx_id, "name": name, "versionInfo": version,
         "downloadLocation": download, "filesAnalyzed": False,
         "licenseConcluded": "NOASSERTION", "licenseDeclared": "NOASSERTION",
         "copyrightText": "NOASSERTION"}
    if sha:
        p["checksums"] = [{"algorithm": "SHA256", "checksumValue": sha}]
    p.update(extra)
    return p


deb_pkg = pkg("SPDXRef-Package-deb", b["package"], b["version"], "NOASSERTION", deb_sha,
              licenseDeclared="MIT", supplier="NOASSERTION",
              externalRefs=[{"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
                             "referenceLocator": f"pkg:deb/termux/{b['package']}@{b['version']}?arch={arch}"}])
rels = [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-Package-deb"}]

if "upstream_tag" in b:
    # pwsh, pwsh-preview: Microsoft's tarball, patched with patchelf.
    upstream_ver = b["upstream_tag"].lstrip("v")
    packages = [
        deb_pkg,
        pkg("SPDXRef-Package-upstream", "PowerShell", upstream_ver, b["upstream_url"],
            b["upstream_sha256"], licenseDeclared="MIT", supplier="Organization: Microsoft Corporation",
            externalRefs=[{"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
                           "referenceLocator": f"pkg:github/PowerShell/PowerShell@{b['upstream_tag']}"}]),
        pkg("SPDXRef-Package-patchelf", "patchelf", b["patchelf_version"],
            "https://github.com/NixOS/patchelf", externalRefs=[
                {"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
                 "referenceLocator": f"pkg:generic/patchelf@{b['patchelf_version']}"}]),
    ]
    rels += [
        {"spdxElementId": "SPDXRef-Package-deb", "relationshipType": "GENERATED_FROM", "relatedSpdxElement": "SPDXRef-Package-upstream"},
        {"spdxElementId": "SPDXRef-Package-patchelf", "relationshipType": "BUILD_TOOL_OF", "relatedSpdxElement": "SPDXRef-Package-deb"},
    ]
else:
    # pwsh-termux-keyring: the public keyring committed to this repository.
    packages = [
        deb_pkg,
        pkg("SPDXRef-Package-keyring-source", b["source_file"], "NOASSERTION",
            "git+https://github.com/EliorMachlev/pwsh-termux", b["source_sha256"],
            licenseDeclared="MIT", supplier="NOASSERTION",
            comment="The public OpenPGP keys the package installs, as committed to the repository."),
    ]
    rels.append({"spdxElementId": "SPDXRef-Package-deb", "relationshipType": "GENERATED_FROM", "relatedSpdxElement": "SPDXRef-Package-keyring-source"})

for d in deps:
    sid = "SPDXRef-Package-dep-" + d.replace("_", "-")
    packages.append(pkg(sid, d, "NOASSERTION", "NOASSERTION",
                        comment="Termux package this one depends on at run time; not part of it."))
    rels.append({"spdxElementId": "SPDXRef-Package-deb", "relationshipType": "DEPENDS_ON", "relatedSpdxElement": sid})

doc = {
    "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
    "name": f"{b['package']}_{b['version']}_{arch} (packaging view)",
    "documentNamespace": f"https://github.com/EliorMachlev/pwsh-termux/spdx/{b['package']}-{b['version']}-{uuid.uuid4()}",
    "creationInfo": {"created": now, "creators": ["Tool: pwsh-termux-spdx-build-view"]},
    "packages": packages, "relationships": rels,
}
json.dump(doc, open(out, "w"), indent=2)
