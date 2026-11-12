# Security

The reporting policy, supported versions and the signing key are in [SECURITY.md](../../../SECURITY.md). This page is the engineering posture behind it.

## What is being protected

Users run what this repository publishes **as themselves, on their phone**. The one thing that must not happen is a user installing a package that is not Microsoft's PowerShell as built by the pipeline. Everything below serves that.

## Threats and mitigations

| Threat | Mitigation | Left over |
|---|---|---|
| **A tampered download** (the tarball changes between Microsoft and us) | Every tarball is checked against Microsoft's `hashes.sha256` for that release; a mismatch stops the build ([packaging](architecture/packaging.md)). | Both files come from the same Microsoft release, so this proves the download is the release, not that Microsoft's release is sound. A compromised upstream release would be packaged. |
| **A tampered package or index in transit or at rest** | apt checks the Ed25519 signature on `InRelease`, then each index file's hash, then each `.deb`'s SHA-256. HTTPS on top. | Anyone who holds the signing key can sign anything (below). |
| **Signing key theft** | The key exists as a GitHub Actions secret used in a single step, never in `GITHUB_ENV`, an output or an artifact, and never printed; a separate copy and a revocation certificate are held outside GitHub. Rotation is documented ([release](release.md#rotating-the-signing-key)). | No passphrase (the workflow is unattended) and no hardware token. No post-quantum signature exists for apt ([SECURITY.md](../../../SECURITY.md#signing-key)). |
| **A wrong key in the keyring package** (the package users install to trust the repository) | The keys are committed in `keys/` (public only, checked by `check-keys.sh` in CI); the package is built reproducibly from them in the unprivileged build job and attested. The publish job, which holds the signing key, rebuilds it and requires the same bytes, requires the signing key's exported public half to be in it, and publishes the attested file ([repository](architecture/repository.md#signing)). | The attestation proves which run and commit built the package from `keys/`, not that those keys are the right ones; that rests on review of changes to `keys/` and on users comparing the fingerprint with SECURITY.md. The first download rests on HTTPS. |
| **A malicious change to the workflows or scripts** | Pull requests run with read-only tokens and no secrets; no `pull_request_target`; zizmor, CodeQL and actionlint audit the workflows; the signing step only runs on `main`, in `update.yaml`. | Branch protection is not enabled, so the maintainer's account is the control: keep two-factor authentication on. |
| **A malicious or hijacked action** | Every action is pinned to a commit SHA; Dependabot proposes updates; harden-runner records egress; zizmor flags impostor commits and unpinned actions. | The maintainer's review of each update. |
| **Domain or Pages takeover** | The domain should be verified in the GitHub account ([release](release.md#custom-domain)), HTTPS is enforced, and the `CNAME` record points only to GitHub. | A dangling record would be exploitable until the domain is verified; verify it. |
| **A leaked secret in the history** | Gitleaks scans the whole history on every change and weekly; GitHub secret scanning and push protection are on. | |
| **A vulnerable dependency** | Dependabot (actions, the two pinned Python tools), Dependency Review on pull requests. The packages' own contents are Microsoft's. | |
| **Abuse of the repository's name** | The packages and site say they are unofficial and unaffiliated; the trademark is acknowledged ([compliance posture](../legal/compliance-posture.md)). | |

## Secrets

| Secret | Used by | Scope |
|---|---|---|
| `GPG_PRIVATE_KEY` | `update.yaml`, one step | The repository's signing key only. Pull requests cannot read it. Its public half is also committed in `keys/`. |
| `GITHUB_TOKEN` | every workflow | Created per run; permissions set per job ([CI / CD](ci-cd.md)). |

There are no other credentials: no deploy keys, no personal access tokens, no third-party services.

## Network

The pipeline contacts only GitHub (the API, the release downloads, Pages, the Actions services). `harden-runner` runs in `audit` mode so unexpected egress is visible in the run's insights. The website loads nothing from another origin ([website](website.md)).

## Code analysis

shellcheck, actionlint, zizmor, CodeQL (`actions`), Gitleaks, lychee, typos, Dependency Review, OpenSSF Scorecard, and the package build itself on every change. None of their findings is suppressed ([exceptions](exceptions.md)).

## What this does not do

No reproducible builds, no build provenance attestations and no separate SBOM are produced today. A package's contents are described exactly in [NOTICE.md](../../../NOTICE.md): Microsoft's tarball, two ELF headers changed, a symlink and a copyright file added.
