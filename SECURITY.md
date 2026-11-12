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

The apt repository is signed with a dedicated key. Its public half is committed to this repository as [`keys/pwsh-termux-archive-keyring.gpg`](keys/pwsh-termux-archive-keyring.gpg), published with the site and installed by the `pwsh-termux-keyring` package (below). apt should trust it for this repository only: the source line names it with `signed-by`, and it does not go into apt's global `trusted.gpg.d`.

| | |
|---|---|
| Algorithm | Ed25519 (OpenPGP v4) |
| Fingerprint | `7086 C70B 4A25 576F E0C0  CE77 E43F B41F 02D0 1FC8` |
| Public key | [`keys/pwsh-termux-archive-keyring.gpg`](keys/pwsh-termux-archive-keyring.gpg) in this repository; on the site as <https://pwsh-termux.machlev.org/pwsh-termux.gpg> (the same file) and `.asc` (armored). Copies are attached to every [release](https://github.com/EliorMachlev/pwsh-termux/releases) made since the keyring package exists, with a `FINGERPRINT.txt` and `pwsh-termux-keyring.deb`; a release keeps the key that was current when it was made. |
| Installed at | `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`, named by `signed-by` in `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list` |
| Expiry | None; replaced by rotation (below) |
| Recovery key | `937A 3D41 5103 CFF8 9DCD  A982 A4B4 5397 EEB6 D752`, also in `keys/RECOVERY`: an offline Ed25519 key, generated on an offline machine and never in GitHub or CI, that never signs the repository except to recover from a lost or compromised online key (below). |

Check the installed key against this fingerprint (`pkg install gnupg` first): `gpg --show-keys $PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`. This page and the website are separate channels, so a mismatch between them is itself a warning sign. The file holds exactly one online key, the one that signs; once set up, also the offline recovery key named in `keys/RECOVERY`; and only during a planned rotation, while `keys/ROTATION` names it, the announced next online key. Every key in it is listed here.

**Post-quantum signing** is not yet possible with apt and GnuPG; the repository uses Ed25519. The reason is in [issue #1](https://github.com/EliorMachlev/pwsh-termux/issues/1). Rotation and revocation, below, are the mitigation.

**Planned rotation** reaches users through `pkg upgrade`: the next key is added to `keys/` (marked by `keys/ROTATION`) and shipped in a new `pwsh-termux-keyring` while the current key still signs; the signer switches after an overlap of 180 days, and the old key is then removed with the marker ([release.md](docs/markDown/engineering/release.md#rotating-the-signing-key)).

**If the online key is compromised or lost**, it cannot hand over to a successor itself, since whoever holds it could sign a keyring of their own. That is what the **recovery key** is for: an offline key held only by the maintainer, never on a networked machine or in CI, whose public half is in every installed keyring. The maintainer publishes an advisory (with the revocation, if compromised), signs a repository carrying a keyring with a new online key using the recovery key, and deploys it with a workflow that holds no key and checks the signature against the recovery key alone; users get the new key with `pkg upgrade` ([release.md](docs/markDown/engineering/release.md#recovery-with-the-offline-key)).

What still needs a manual reinstall of `pwsh-termux-keyring.deb` from the site, with a fingerprint check: a user who does not run `pkg upgrade` within an overlap or recovery window (180 days); a key added by hand; and a compromised online key while the recovery key is lost. Recovery also needs the hosting and the maintainer's GitHub account to be intact. A revocation certificate for the online key is stored separately from the GitHub secret.

### The keyring package

`pwsh-termux-keyring` (`Architecture: all`) is what the install line downloads from <https://pwsh-termux.machlev.org/pwsh-termux-keyring.deb>. It installs two files and nothing else, with no maintainer scripts: the public key file from `keys/` at `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`, and `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list` with `deb [signed-by=/data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg] https://pwsh-termux.machlev.org stable main`. It is built once, by [`scripts/build-keyring.sh`](scripts/build-keyring.sh) in the same unprivileged job as the other packages (deterministically: CI builds it twice and compares), and has the same SBOMs and build provenance. Before anything is signed, a job with a read-only token and no signing key checks that provenance (`gh attestation verify`, pinned to `build-packages.yaml`, to the commit being published and to GitHub-hosted runners). The publish job then refuses to sign or publish unless the package is that verified file, it ships the committed `keys/` file byte for byte, and the signing key is the online key in `keys/` (or, during a marked rotation, the next one), never the recovery key; it publishes the verified file as it is. Together these prove that the package was built by this repository's workflow from the published commit and contains exactly the committed keys, whose online key signs the index; they do not prove that the committed key is the right one, which is why you compare its fingerprint with this page.

The first download rests on HTTPS, as any first key download does. To check it:

```bash
pkg install gnupg
gpg --show-keys $PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg     # compare with the fingerprint above
gh attestation verify $TMPDIR/pwsh-termux-keyring.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
```

**Handling.** The private key is a GitHub Actions secret (`GPG_PRIVATE_KEY`) used in one workflow step on GitHub's runners, never written to the repository or to later steps; the maintainer holds a separate copy outside GitHub. The key has no passphrase, because the workflow runs unattended; its protection is GitHub's secret storage and the workflow's pinned, audited actions.

## What a package contains

Each `.deb` holds Microsoft's `linux-arm64` tarball for the release, verified against Microsoft's `hashes.sha256` before use, with exactly these differences:

- the ELF interpreter and rpath of the two executables with a loader (`pwsh`, `createdump`) are changed to point at Termux's glibc;
- a `bin/<package>` symlink and a `share/doc/<package>/copyright` file are added.

No PowerShell file is otherwise modified. [NOTICE.md](NOTICE.md) lists the details; no separate SBOM is published.

## Software Bill of Materials (SBOM) and build provenance

Each GitHub release carries, for its `.deb`, four SBOMs (and the same four for the `pwsh-termux-keyring` package it carries), all listed in the release's `SHA256SUMS`: `*.cdx.json` (CycloneDX 1.6, from Syft) and three SPDX files from three generators, each at the highest SPDX version the tool writes: `*.build.spdx.json` (SPDX 2.3, the packaging view: the official tarball and its SHA-256, the patching tool, the dependencies; for the keyring, the committed key file and its SHA-256), `*.syft.spdx3.json` (SPDX 3.0.1, Syft over the package's files) and `*.msft.spdx3.json` (SPDX 3.0, Microsoft's SBOM tool over the package's files). The generators are pinned by version and SHA-256, and each file is validated when it is written.

The `.deb` and the four SBOMs are attested: GitHub signs a statement of which commit and workflow run built each file ([SLSA build level 3](https://slsa.dev) by GitHub's recipe, in a reusable workflow so the signer is `build-packages.yaml` itself). The statements are on GitHub and attached to the release as a JSON Lines file in the in-toto format, named the way OpenSSF Scorecard's Signed-Releases check expects. To verify:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

`SHA256SUMS` comes from the same release as the files it lists, so only the attestation proves where a file came from. The apt repository's own signature (the key above) is a separate check and covers what `apt` installs.

## Index freshness (Valid-Until)

The signed index (`dists/stable/InRelease`) carries a `Valid-Until` date 14 days after its `Date`. apt refuses an index past that date, so an attacker who controls a user's connection or a mirror cannot keep serving an old, validly signed index (one that hides a security update) for more than 14 days: a *freeze* or *replay* attack is bounded.

The daily workflow re-signs and redeploys the index every day, whether or not Microsoft published anything, so the date moves on by itself and no commit is made. An unchanged release rebuilds to the same bytes, so `Packages` and every `.deb` stay byte-identical: a daily re-sign changes only `InRelease` (and `Release`, `Release.gpg`), clients re-download that small file, and no upgrade is offered.

**If the pipeline is broken for more than 14 days**, apt on every device stops loudly instead of silently serving stale packages: `pkg update` prints *Release file for https://pwsh-termux.machlev.org/dists/stable/InRelease is expired (invalid since …). Updates for this repository will not be applied.* Installed packages keep working; nothing new installs from this repository until the index is re-signed. A daily check of the live index opens an issue when fewer than 7 days are left (or it cannot be fetched or verified), so the maintainer hears about it first. An index signed with the offline recovery key has the same 14-day limit.

**If GitHub pauses the schedules.** GitHub disables a public repository's scheduled workflows after 60 days without repository activity, which would stop the daily re-sign and the daily check together. Three small jobs, each with only the workflow's own `GITHUB_TOKEN` and `actions: write` (no personal token, no commit, no key), renew every scheduled workflow through GitHub's API, daily and twice a week, each renewing the others; a workflow the maintainer turned off by hand stays off; and the daily check opens an issue if it finds one disabled for inactivity. GitHub documents the 60-day rule and the API; it does not document that renewing a workflow restarts the 60-day count. That is assumed, from common practice, and stated as such in [ci-cd.md](docs/markDown/engineering/ci-cd.md#schedule-keep-alive). If it were wrong, every schedule could stop on the same day with nothing in the repository left to raise the alarm (users report an e-mail from GitHub when it happens; GitHub does not document one), and the maintainer would have the index's 14 days to re-enable them before `pkg update` fails; any commit on `main` also restarts the count. So when `main` has had no commit for 30 days, a weekly workflow also pushes one commit that changes only a file named `keep.alive` (a timestamp), the kind of activity GitHub does document ([ci-cd.md](docs/markDown/engineering/ci-cd.md#keep-alive-commit)).

## Commits on main and the keep-alive deploy key

`main` is protected by a repository ruleset: signed commits, a successful Pages deployment and clean code scanning (CodeQL, Scorecard, zizmor), no deletion, no force push. GitHub Actions cannot bypass a ruleset in a personal repository, so the keep-alive commit is pushed with the repository's **only deploy key**, which a ruleset for `main` alone lets bypass the signature, deployment and code-scanning rules (never deletion, force push or branch creation). The maintainer sets that ruleset up once this is merged; until then the push is refused and nothing is committed. Its private half is a secret of an environment that only `main`'s workflows can use, held in memory by one step of one job, and the script pushes nothing but a one-parent commit that sets `keep.alive` to a timestamp, as `github-actions[bot]`, then marks it with the commit status `keepalive/pushed`.

Every commit on `main` is audited, on each push and daily: it must be signed and verified by a trusted account (pull request merges by GitHub, the maintainer), or be exactly such a keep-alive commit carrying that status, which only a workflow's own token can create. Anything else opens the issue *Unexpected unsigned commit on main*, which means the deploy key may have leaked and must be rotated ([release.md](docs/markDown/engineering/release.md#rotating-the-keep-alive-deploy-key)). This is detection, not prevention: whoever holds the key can push any commit to `main`, workflow changes included, and so reach the repository's secrets, the signing key among them; the same push could change the audit. The protection is in where the key lives and who can use it. There must never be a second deploy key: a deploy-key bypass applies to all of them.

## Verifying a download

`apt` checks the signed index and each package's SHA-256 for you. To check a `.deb` from a [release](https://github.com/EliorMachlev/pwsh-termux/releases) by hand, compare `sha256sum <file>` with the `SHA256:` line for that file in <https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages>, which is signed in `InRelease`.

## Related documents

- [`docs/markDown/engineering/security.md`](docs/markDown/engineering/security.md): full security posture (supply chain, secrets, signing, code analysis).
- [`docs/markDown/legal/compliance-posture.md`](docs/markDown/legal/compliance-posture.md): regulatory applicability posture.
- [`docs/markDown/legal/privacy-policy.md`](docs/markDown/legal/privacy-policy.md): privacy notice.
- [`docs/markDown/legal/accessibility-statement.md`](docs/markDown/legal/accessibility-statement.md): accessibility statement.
- [`docs/markDown/legal/terms-of-service.md`](docs/markDown/legal/terms-of-service.md): terms of service.
