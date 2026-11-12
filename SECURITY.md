# Security Policy

## Supported Versions

Only what the repository currently publishes is supported: the latest `pwsh` (stable) and, while it exists, the latest `pwsh-preview`.

| Version | Supported |
|---------|-----------|
| Latest published build | Yes |
| Older builds (release assets) | No |

## Reporting a Vulnerability

Please **do not** open a public GitHub Issue for security vulnerabilities.

Report vulnerabilities privately via [GitHub's private vulnerability reporting](https://github.com/EliorMachlev/pwsh-termux/security/advisories/new).

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Package and version (`pkg list-installed | grep pwsh`) and your device architecture

You will receive a response within 7 days. If the vulnerability is confirmed, a fix will be published as soon as possible, and you will be credited in the advisory unless you prefer otherwise.

### Coordinated Vulnerability Disclosure

pwsh-termux follows a **coordinated disclosure** model:

1. Report privately via the channel above.
2. Acknowledgement target: **7 days**.
3. Triage and severity assessment: **14 days**.
4. Fix + coordinated public disclosure: as soon as a fix is available. Reporter is credited unless anonymity is requested.
5. If a reported issue is not a vulnerability, the reporter is told why within the triage window.

Public disclosure before a fix is available is discouraged. Reporters who wish to disclose on a fixed schedule should say so in the initial report; a 90-day default disclosure window is honoured.

## Scope

In scope: the packaging scripts (`scripts/`), the workflows (`.github/`), the website (`docs/`), the signing key's handling, and the published apt repository and `.deb` files.

Out of scope, and best reported to their owners:

- Vulnerabilities **in PowerShell itself**: report them to Microsoft ([PowerShell security policy](https://github.com/PowerShell/PowerShell/security/policy)). If a PowerShell fix is released, this repository picks it up on its next daily run.
- Vulnerabilities in Termux, in Termux's glibc packages, or in GitHub.

## Signing key

The apt repository is signed with a dedicated key. Its public half is published with the site, and it is the only key apt should trust for this repository.

| | |
|---|---|
| Algorithm | Ed25519 (OpenPGP v4) |
| Fingerprint | `7086 C70B 4A25 576F E0C0  CE77 E43F B41F 02D0 1FC8` |
| Public key | <https://pwsh-termux.machlev.org/pwsh-termux.gpg> (binary) and `.asc` (armored). Copies are attached to every [release](https://github.com/EliorMachlev/pwsh-termux/releases) with a `FINGERPRINT.txt`; a release keeps the key that was current when it was made. |
| Expiry | None; replaced by rotation (below) |

Check the downloaded key against this fingerprint: `gpg --show-keys $PREFIX/etc/apt/trusted.gpg.d/pwsh-termux.gpg`. This page and the website are separate channels, so a mismatch between them is itself a warning sign.

**Post-quantum signing** is not yet possible with apt and GnuPG; the repository uses Ed25519. The reason is in [issue #1](https://github.com/EliorMachlev/pwsh-termux/issues/1). Rotation and revocation, below, are the mitigation.

**If the key is compromised or lost**, the maintainer will publish a revocation, generate a new key, redeploy the repository signed with it, and announce the new fingerprint in a GitHub security advisory and on the website. Users then replace the file in `$PREFIX/etc/apt/trusted.gpg.d/`. A revocation certificate was generated when the key was created and is stored separately from the GitHub secret.

**Handling.** The private key is a GitHub Actions secret (`GPG_PRIVATE_KEY`) used in one workflow step on GitHub's runners, never written to the repository or to later steps; the maintainer holds a separate copy outside GitHub. The key has no passphrase, because the workflow runs unattended; its protection is GitHub's secret storage and the workflow's pinned, audited actions.

## What a package contains

Each `.deb` holds Microsoft's `linux-arm64` tarball for the release, verified against Microsoft's `hashes.sha256` before use, with exactly these differences:

- the ELF interpreter and rpath of the two executables with a loader (`pwsh`, `createdump`) are changed to point at Termux's glibc;
- a `bin/<package>` symlink and a `share/doc/<package>/copyright` file are added.

No PowerShell file is otherwise modified. [NOTICE.md](NOTICE.md) lists the details; no separate SBOM is published.

## Software Bill of Materials (SBOM) and build provenance

Each GitHub release carries, for its `.deb`, four SBOMs, all listed in the release's `SHA256SUMS`: `*.cdx.json` (CycloneDX 1.6, from Syft) and three SPDX files from three generators, each at the highest SPDX version the tool writes: `*.build.spdx.json` (SPDX 2.3, the packaging view: the official tarball and its SHA-256, the patching tool, the dependencies), `*.syft.spdx3.json` (SPDX 3.0.1, Syft over the package's files) and `*.msft.spdx3.json` (SPDX 3.0, Microsoft's SBOM tool over the package's files). The generators are pinned by version and SHA-256, and each file is validated when it is written.

The `.deb` and the four SBOMs are attested: GitHub signs a statement of which commit and workflow run built each file ([SLSA build level 3](https://slsa.dev) by GitHub's recipe, in a reusable workflow so the signer is `build-packages.yaml` itself). The statements are on GitHub and attached to the release as `pwsh-termux.intoto.jsonl`. To verify:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

`SHA256SUMS` comes from the same release as the files it lists, so only the attestation proves where a file came from. The apt repository's own signature (the key above) is a separate check and covers what `apt` installs.

## Verifying a download

`apt` checks the signed index and each package's SHA-256 for you. To check a `.deb` from a [release](https://github.com/EliorMachlev/pwsh-termux/releases) by hand, compare `sha256sum <file>` with the `SHA256:` line for that file in <https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages>, which is signed in `InRelease`.

## Related documents

- [`docs/markDown/engineering/security.md`](docs/markDown/engineering/security.md): full security posture (supply chain, secrets, signing, code analysis).
- [`docs/markDown/legal/compliance-posture.md`](docs/markDown/legal/compliance-posture.md): regulatory applicability posture.
- [`docs/markDown/legal/privacy-policy.md`](docs/markDown/legal/privacy-policy.md): privacy notice.
- [`docs/markDown/legal/accessibility-statement.md`](docs/markDown/legal/accessibility-statement.md): accessibility statement.
- [`docs/markDown/legal/terms-of-service.md`](docs/markDown/legal/terms-of-service.md): terms of service.
