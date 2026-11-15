# Security Policy

## Supported Versions

Only what the repository currently publishes: the latest `pwsh` (stable) and, while it exists, the latest `pwsh-preview`. Older builds (release assets) are not supported.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue. Report privately through [GitHub's private vulnerability reporting](https://github.com/EliorMachlev/pwsh-termux/security/advisories/new).

Include:

- a description of the vulnerability;
- steps to reproduce;
- the potential impact;
- the package and version (`pkg list-installed | grep pwsh`) and your device architecture.

### Coordinated Vulnerability Disclosure

1. You report privately, as above.
2. Acknowledgement within **7 days**.
3. Triage and severity assessment within **14 days**. If it is not a vulnerability, you are told why in this window.
4. A fix is published as soon as possible, with coordinated public disclosure. You are credited in the advisory unless you ask not to be.

Please do not disclose publicly before a fix is available. To disclose on a fixed schedule, say so in the report; a 90-day disclosure window is honoured by default.

## Scope

In scope: the packaging scripts (`scripts/`), the workflows (`.github/`), the website (`docs/`), the signing key's handling, and the published apt repository and `.deb` files.

Out of scope, report to their owners:

- PowerShell itself: Microsoft ([PowerShell security policy](https://github.com/PowerShell/PowerShell/security/policy)). A released fix is picked up by the next daily run.
- Termux, Termux's glibc packages, GitHub.

## Signing key

The apt repository is signed with a dedicated key. apt trusts it for this repository only: the source line names it with `signed-by`; it is not in apt's global `trusted.gpg.d`.

| | |
|---|---|
| Algorithm | Ed25519 (OpenPGP v4) |
| Fingerprint | `7086 C70B 4A25 576F E0C0  CE77 E43F B41F 02D0 1FC8` |
| Recovery key | `937A 3D41 5103 CFF8 9DCD  A982 A4B4 5397 EEB6 D752` |
| Expiry | None; replaced by rotation |

CI reads the fingerprint from this table and checks it against `keys/`.

- **Recovery key:** also in `keys/RECOVERY`. An offline Ed25519 key, generated offline and never in GitHub or CI. It signs only to recover from a lost or compromised online key.
- **Public key:** [`keys/pwsh-termux-archive-keyring.gpg`](keys/pwsh-termux-archive-keyring.gpg); on the site as <https://pwsh-termux.machlev.org/pwsh-termux.gpg> (the same file) and `.asc` (armored). Every [release](https://github.com/EliorMachlev/pwsh-termux/releases) since the keyring package exists carries a copy, a `FINGERPRINT.txt` and `pwsh-termux-keyring.deb`, as they were when it was made.
- **Installed at:** `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`, named by `signed-by` in `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list`.

### Checking the key

```bash
pkg install gnupg
gpg --show-keys $PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg     # compare with the fingerprints above
```

Optionally, check the keyring package's build provenance (needs `pkg install gh` and `gh auth login`):

```bash
curl -fsSL https://pwsh-termux.machlev.org/pwsh-termux-keyring.deb -o $TMPDIR/pwsh-termux-keyring.deb
gh attestation verify $TMPDIR/pwsh-termux-keyring.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml --deny-self-hosted-runners
```

The file holds the online signing key, the recovery key and, only during a planned rotation (while `keys/ROTATION` names it), the announced next online key. Every key in it is listed here. This page and the website are separate channels: a mismatch between them is a warning sign. The first download rests on HTTPS, as any first key download does.

### Rotation and recovery

- **Planned rotation** reaches users through `pkg upgrade`. The next key is added to `keys/` (marked by `keys/ROTATION`) and shipped in a new `pwsh-termux-keyring` while the current key still signs. After an overlap of 180 days the signer switches and the old key is removed ([rotation](docs/markDown/engineering/release.md#rotating-the-signing-key)).
- **A compromised or lost online key** cannot hand over to a successor itself. The maintainer publishes an advisory (with the revocation, if compromised) and uses the offline recovery key, whose public half is in every installed keyring, to sign a repository with a keyring carrying a new online key. A workflow that holds no key deploys it after checking the signature against the recovery key alone; users get the new key with `pkg upgrade` ([recovery](docs/markDown/engineering/release.md#recovery-with-the-offline-key)).
- **A manual reinstall** of `pwsh-termux-keyring.deb` from the site, with a fingerprint check, is needed by a user who does not run `pkg upgrade` within the 180-day window, for a key added by hand, and if the online key is compromised while the recovery key is lost. Recovery also needs the hosting and the maintainer's GitHub account intact.

### The keyring package

`pwsh-termux-keyring` (`Architecture: all`) is what the install line downloads from <https://pwsh-termux.machlev.org/pwsh-termux-keyring.deb>. It installs two files, with no maintainer scripts:

- the public key file from `keys/`, at `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`;
- `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list` with `deb [signed-by=/data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg] https://pwsh-termux.machlev.org stable main`.

[`scripts/build-keyring.sh`](scripts/build-keyring.sh) builds it deterministically (CI builds it twice and compares) in the unprivileged build job, with the same SBOMs and build provenance as the other packages. Before anything is signed, a job with a read-only token and no signing key verifies that provenance (`gh attestation verify`, pinned to `build-packages.yaml`, the published commit and GitHub-hosted runners). The publish job refuses to sign or publish unless the package is that verified file, ships the committed `keys/` file byte for byte, and the signer is the online key (never the recovery key). This proves the package holds exactly the committed keys; it does not prove the committed key is the right one, which is why you compare fingerprints with this page.

### Handling

The private key is a GitHub Actions secret (`GPG_PRIVATE_KEY`) of an environment only `main` can use, read by one workflow step on GitHub's runners and never written to the repository or later steps. The maintainer holds a separate copy and a revocation certificate outside GitHub. The key is passphrase-protected, but the passphrase (`GPG_PASSPHRASE`) is in the same environment because the workflow runs unattended, so it protects only a copy of the key on its own. The real protection is GitHub's secret storage, the environment limited to `main`, and the workflow's pinned, audited actions. Details: [security engineering](docs/markDown/engineering/security.md).

## What a package contains

Microsoft's `linux-arm64` tarball for the release, verified against Microsoft's `hashes.sha256`, with two ELF headers (`pwsh`, `createdump`) pointed at Termux's glibc and a `bin/<package>` symlink and `share/doc/<package>/copyright` file added. Nothing else is modified ([NOTICE.md](NOTICE.md)).

## Software Bill of Materials (SBOM) and build provenance

Each GitHub release carries four SBOMs for its `.deb` (and four for the `pwsh-termux-keyring` package it carries), all listed in the release's `SHA256SUMS`:

1. `*.cdx.json`: CycloneDX 1.6, from Syft.
2. `*.build.spdx.json`: SPDX 2.3, the packaging view (the official tarball and its SHA-256, the patching tool, the dependencies; for the keyring, the committed key file and its SHA-256).
3. `*.syft.spdx3.json`: SPDX 3.0.1, Syft over the package's files.
4. `*.msft.spdx3.json`: SPDX 3.0, Microsoft's SBOM tool over the package's files.

The generators are pinned by version and SHA-256, and each file is validated when written.

The `.deb` and its SBOMs are attested: GitHub signs a statement of which commit and workflow run built each file ([SLSA build level 3](https://slsa.dev), in a reusable workflow so the signer is `build-packages.yaml`). The statements are on GitHub and attached to the release as an in-toto JSON Lines file. To verify:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

`SHA256SUMS` comes from the same release as the files it lists, so only the attestation proves where a file came from. The apt signature is a separate check and covers what `apt` installs.

## Index freshness (Valid-Until)

The signed index (`dists/stable/InRelease`) carries a `Valid-Until` date 14 days after its `Date`, and apt refuses it after that. So an attacker who controls a connection or a mirror can serve an old, validly signed index (one that hides a security update) for at most 14 days.

The daily workflow re-signs and redeploys the index whether or not Microsoft published anything, without a commit. Unchanged releases rebuild to the same bytes, so only `InRelease` (and `Release`, `Release.gpg`) changes and no upgrade is offered.

If the pipeline is broken for more than 14 days, `pkg update` stops loudly instead of serving stale packages: *Release file for https://pwsh-termux.machlev.org/dists/stable/InRelease is expired (invalid since …). Updates for this repository will not be applied.* Installed packages keep working. A daily check of the live index opens an issue when fewer than 7 days are left, or when it cannot fetch or verify the index. An index signed with the recovery key has the same limit.

GitHub disables a public repository's schedules after 60 days without activity, which would stop the re-sign. Scheduled jobs re-enable each other, and a commit that only touches `keep.alive` is pushed when `main` has been quiet for 30 days ([threat model](docs/markDown/engineering/security/threat-model.md#schedules-disabled-for-inactivity)).

## Commits on main

Every change reaches `main` through a pull request on signed commits that passes 19 required checks, merged as a squash commit that GitHub signs; the maintainer's admin role cannot bypass that ([rulesets](docs/markDown/engineering/release.md#rulesets)). The one exception is the keep-alive commit, pushed with the repository's only deploy key. Every commit on `main` is audited on each push and daily; anything unexpected opens the issue *Unexpected unsigned commit on main*, which means the deploy key must be rotated ([threat model](docs/markDown/engineering/security/threat-model.md#leaked-keep-alive-deploy-key)).

## Verifying a download

`apt` checks the signed index and each package's SHA-256 for you. To check a `.deb` from a [release](https://github.com/EliorMachlev/pwsh-termux/releases) by hand, compare `sha256sum <file>` with the `SHA256:` line for that file in <https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages>, which `InRelease` signs.

### Verifying a release tag

Each release's tag (`<package>-<version>`; a `~` in the version is written `-`) is an annotated tag signed with the **signing key above**, on the commit that built the release, tagged by `github-actions[bot]`. To check one:

```bash
git clone https://github.com/EliorMachlev/pwsh-termux && cd pwsh-termux   # or, in a clone: git fetch --tags
curl -fsSL https://pwsh-termux.machlev.org/pwsh-termux.asc | gpg --import  # or: gpg --import keys/pwsh-termux-archive-keyring.gpg
git tag -v pwsh-<version>
```

`git tag -v` must print *Good signature from "pwsh-termux repository signing key"* and a *Primary key fingerprint* equal to `7086 C70B 4A25 576F E0C0  CE77 E43F B41F 02D0 1FC8`. gpg's warning that the key is not certified with a trusted signature only means you have not signed it yourself. A tag signed by any other key, or unsigned, did not come from this pipeline.

GitHub shows these tags as unverified: the key is deliberately on no GitHub account, so it cannot make commits that GitHub would show as the maintainer's ([signed release tags](docs/markDown/engineering/release.md#signed-release-tags)). Tags made before tag signing, `pwsh-7.7.0-1` included, are lightweight and unsigned, and stay so; for those, use the build provenance above.

## Related documents

- [Security engineering](docs/markDown/engineering/security.md): threat model, assurance case, supply chain, secrets.
- [Compliance posture](docs/markDown/legal/compliance-posture.md), [privacy policy](docs/markDown/legal/privacy-policy.md), [accessibility statement](docs/markDown/legal/accessibility-statement.md), [terms of service](docs/markDown/legal/terms-of-service.md).
