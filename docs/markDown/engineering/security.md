# Security

The reporting policy, supported versions and the signing key are in [SECURITY.md](../../../SECURITY.md). This page is the engineering posture behind it.

## What is being protected

Users run what this repository publishes **as themselves, on their phone**. The one thing that must not happen is a user installing a package that is not Microsoft's PowerShell as built by the pipeline. Everything below serves that.

## Threats and mitigations

| Threat | Mitigation | Left over |
|---|---|---|
| **A tampered download** (the tarball changes between Microsoft and us) | Every tarball is checked against Microsoft's `hashes.sha256` for that release; a mismatch stops the build ([packaging](architecture/packaging.md)). | Both files come from the same Microsoft release, so this proves the download is the release, not that Microsoft's release is sound. A compromised upstream release would be packaged. |
| **A tampered package or index in transit or at rest** | apt checks the Ed25519 signature on `InRelease`, then each index file's hash, then each `.deb`'s SHA-256. HTTPS on top. | Anyone who holds the signing key can sign anything (below). |
| **A frozen or replayed index** (an old, validly signed index served again to hide an update) | `Release` carries `Valid-Until` = `Date` + 14 days, and apt refuses it afterwards. The daily run re-signs the index (no commit), which moves the window on; the same packages give byte-identical `Packages` and `.deb` files, so only `InRelease` changes. `verify-recovery-repo.sh` and `recovery-sign.sh` refuse an index whose window is longer than 14 days or has fewer than 7 left. [`staleness.yaml`](../../../.github/workflows/staleness.yaml) checks the live index daily (reachable, signed by a key in `keys/`, at least 7 days left) and opens an issue otherwise. | Within the 14 days, a replayed index is still accepted. If the pipeline stays broken for more than 14 days, `pkg update` fails for every user with an *expired* error until the index is re-signed: a loud failure instead of silent staleness. GitHub disables a public repository's schedules after 60 days without activity, which would stop both the re-sign and the check: see the next row. |
| **Schedules disabled for inactivity** (no commit on `main` for 60 days stops the daily re-sign, and 14 days later the index expires) | Three small jobs (`update.yaml` and `staleness.yaml` daily, `keepalive.yaml` twice a week) renew every scheduled workflow through the REST API with the job's own `GITHUB_TOKEN` and `actions: write`, each renewing the others ([keep-alive](ci-cd.md#schedule-keep-alive)); no personal token, no commit, no key. A workflow turned off by hand stays off. `staleness.yaml` opens an issue if it finds one in `disabled_inactivity`, and prints the age of the last commit on `main`. | GitHub does not document that an enable call restarts the 60-day count; that is assumed, from community practice. If it does not, all schedules can stop together on day 60 and only the maintainer (re-enable, or a merge to `main`) restarts them, within the index's 14 days. |
| **Signing key theft** | The key exists as a GitHub Actions secret used in a single step, never in `GITHUB_ENV`, an output or an artifact, and never printed; a separate copy and a revocation certificate are held outside GitHub. Rotation is documented ([release](release.md#rotating-the-signing-key)); an offline recovery key lets users move to a new key through `pkg upgrade` ([release](release.md#recovery-with-the-offline-key)). | No passphrase (the workflow is unattended) and no hardware token. If the recovery key is lost as well, a stolen key means a manual keyring reinstall for every user. No post-quantum signature exists for apt ([SECURITY.md](../../../SECURITY.md#signing-key)). |
| **A wrong key in the keyring package** (the package users install to trust the repository) | `keys/` holds exactly one online key, the signer, plus only keys named by `keys/RECOVERY` (offline recovery key) or `keys/ROTATION` (next online key); `check-keys.sh` enforces it in CI and in the publish job. The package is built in the unprivileged build job and attested; a job without the signing key verifies that attestation (workflow, commit, hosted runner), and the publish job signs only if the package is that verified file, ships `keys/` byte for byte, and the signer is the online key, never the recovery key ([repository](architecture/repository.md#signing)). | These prove the package came from this repository's workflow at the published commit and holds the committed keys; not that the committed keys are the right ones, which rests on review of `keys/` and on users comparing fingerprints with SECURITY.md. The first download rests on HTTPS. |
| **A malicious change to the workflows or scripts** | Pull requests run with read-only tokens and no secrets; no `pull_request_target`; zizmor, CodeQL and actionlint audit the workflows; the signing step only runs on `main`, in `update.yaml`. | Branch protection is not enabled, so the maintainer's account is the control: keep two-factor authentication on. |
| **A malicious or hijacked action** | Every action is pinned to a commit SHA; Dependabot proposes updates; harden-runner records egress; zizmor flags impostor commits and unpinned actions. | The maintainer's review of each update. |
| **Domain or Pages takeover** | The domain should be verified in the GitHub account ([release](release.md#custom-domain)), HTTPS is enforced, and the `CNAME` record points only to GitHub. | A dangling record would be exploitable until the domain is verified; verify it. |
| **A lost or unreadable recovery-key backup**, noticed only when it is needed | [`key-review.yaml`](../../../.github/workflows/key-review.yaml) opens an issue every January: check the offline backups and revocation certificates by hand, offline, and review the rotation plan. The issue holds no key material. | It is a reminder; the check itself is the maintainer's. |
| **A leaked secret in the history** | Gitleaks scans the whole history on every change and weekly; GitHub secret scanning and push protection are on. | |
| **A vulnerable dependency** | Dependabot (actions, the two pinned Python tools), Dependency Review on pull requests. The packages' own contents are Microsoft's. | |
| **Abuse of the repository's name** | The packages and site say they are unofficial and unaffiliated; the trademark is acknowledged ([compliance posture](../legal/compliance-posture.md)). | |

## Secrets

| Secret | Used by | Scope |
|---|---|---|
| `GPG_PRIVATE_KEY` | `update.yaml`, one step | The repository's signing key only. Pull requests cannot read it. Its public half is also committed in `keys/`. |
| `GITHUB_TOKEN` | every workflow | Created per run; permissions set per job ([CI / CD](ci-cd.md)). `actions: write` (enable a workflow) only on the three keep-alive jobs, which run nothing but `keep-schedules-alive.sh`. |

There are no other credentials: no deploy keys, no personal access tokens, no third-party services.

## Network

The pipeline contacts only GitHub (the API, the release downloads, Pages, the Actions services). `harden-runner` runs in `audit` mode so unexpected egress is visible in the run's insights. The website loads nothing from another origin ([website](website.md)).

## Code analysis

shellcheck, actionlint, zizmor, CodeQL (`actions`), Gitleaks, lychee, typos, Dependency Review, OpenSSF Scorecard, and the package build itself on every change. None of their findings is suppressed ([exceptions](exceptions.md)).

## What this does not do

The PowerShell packages are built reproducibly in the sense that matters here: the same release, script and tools give the same bytes (every timestamp is the newest file time in Microsoft's tarball, xz is single-threaded, `Installed-Size` is summed from file sizes), and CI builds the package twice and compares. A runner image update that changes `dpkg-deb`, xz or `patchelf` could still change the bytes once, for the same version: apt then downloads a new `Packages` but offers no upgrade. No independent rebuild is compared against what is published. Their SBOMs and build provenance are described in [SECURITY.md](../../../SECURITY.md#software-bill-of-materials-sbom-and-build-provenance). A package's contents are described exactly in [NOTICE.md](../../../NOTICE.md): Microsoft's tarball, two ELF headers changed, a symlink and a copyright file added.
