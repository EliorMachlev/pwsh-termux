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
| Public key | <https://pwsh-termux.machlev.org/pwsh-termux.gpg> (binary) and `.asc` (armored) |
| Expiry | None; replaced by rotation (below) |

Check the downloaded key against this fingerprint: `gpg --show-keys $PREFIX/etc/apt/trusted.gpg.d/pwsh-termux.gpg`. This page and the website are separate channels, so a mismatch between them is itself a warning sign.

**Post-quantum signing is not yet possible.** This is a limit of today's tools, not a choice: the maintainer would use a quantum-resistant signature if apt could verify one, and will switch when it can. GnuPG 2.5 implements only post-quantum *encryption* (ML-KEM), and apt accepts only RSA, Ed25519, Ed448 and the NIST/Brainpool curves. Ed448 was tried: GnuPG generates it as a version-5 key whose 64-character fingerprint apt 2.8 cannot match, so apt reports a bad signature. Ed25519 is the strongest algorithm apt can verify. Until a post-quantum option works, rotation and revocation (below) are the mitigation.

**If the key is compromised or lost**, the maintainer will publish a revocation, generate a new key, redeploy the repository signed with it, and announce the new fingerprint in a GitHub security advisory and on the website. Users then replace the file in `$PREFIX/etc/apt/trusted.gpg.d/`. A revocation certificate was generated when the key was created and is stored separately from the GitHub secret.

**Handling.** The private key is a GitHub Actions secret (`GPG_PRIVATE_KEY`) used in one workflow step on GitHub's runners, never written to the repository or to later steps; the maintainer holds a separate copy outside GitHub. The key has no passphrase, because the workflow runs unattended; its protection is GitHub's secret storage and the workflow's pinned, audited actions.

## What a package contains

Each `.deb` holds Microsoft's `linux-arm64` tarball for the release, verified against Microsoft's `hashes.sha256` before use, with exactly these differences:

- the ELF interpreter and rpath of the two executables with a loader (`pwsh`, `createdump`) are changed to point at Termux's glibc;
- a `bin/<package>` symlink and a `share/doc/<package>/copyright` file are added.

No PowerShell file is otherwise modified. [NOTICE.md](NOTICE.md) lists the details; no separate SBOM is published.

## Verifying a download

`apt` checks the signed index and each package's SHA-256 for you. To check a `.deb` from a [release](https://github.com/EliorMachlev/pwsh-termux/releases) by hand, compare `sha256sum <file>` with the `SHA256:` line for that file in <https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages>, which is signed in `InRelease`.

## Related documents

- [`docs/markDown/engineering/security.md`](docs/markDown/engineering/security.md): full security posture (supply chain, secrets, signing, code analysis).
- [`docs/markDown/legal/compliance-posture.md`](docs/markDown/legal/compliance-posture.md): regulatory applicability posture.
- [`docs/markDown/legal/privacy-policy.md`](docs/markDown/legal/privacy-policy.md): privacy notice.
- [`docs/markDown/legal/accessibility-statement.md`](docs/markDown/legal/accessibility-statement.md): accessibility statement.
- [`docs/markDown/legal/terms-of-service.md`](docs/markDown/legal/terms-of-service.md): terms of service.
