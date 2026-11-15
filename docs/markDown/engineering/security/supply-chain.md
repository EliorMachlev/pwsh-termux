# Supply chain

## Input

The build downloads Microsoft's `linux-arm64` tarball from its GitHub release and stops unless it matches Microsoft's `hashes.sha256` ([packaging](../architecture/packaging.md)). A package is that tarball with two ELF headers changed and a symlink and a copyright file added ([NOTICE.md](../../../../NOTICE.md)).

## Reproducible packages

The same release, script and tools give the same bytes: every timestamp is the newest file time in Microsoft's tarball, xz is single-threaded, and `Installed-Size` is summed from file sizes. CI builds each package twice and compares.

Limits:

- A runner image update that changes `dpkg-deb`, xz or `patchelf` can change the bytes once for the same version. apt then downloads a new `Packages` but offers no upgrade.
- No independent rebuild is compared against what is published.

## SBOMs and provenance

Every release carries a CycloneDX and three SPDX SBOMs and signed build provenance for each `.deb`. What they hold and how to verify them: [SECURITY.md](../../../../SECURITY.md#software-bill-of-materials-sbom-and-build-provenance).

## Actions and dependencies

- Every action is pinned to a commit SHA with its version in a comment.
- Dependabot updates the actions, the pinned Python tools (zizmor, typos, Hypothesis, coverage.py) and the site's npm checkers; Dependency Review runs on pull requests.
- harden-runner runs first in each job, in `audit` mode, so unexpected egress shows in the run's insights.

## Network

The pipeline contacts only GitHub: the API, the release downloads, Pages and the Actions services. The website loads nothing from another origin ([website](../website.md)).

## Code analysis

On every change: shellcheck, jactionlint, zizmor, CodeQL (`actions`), Gitleaks, lychee, typos, Dependency Review, Hypothesis fuzzing of `spdx-build-view.py`, test coverage with a floor, and a real package build. OpenSSF Scorecard runs on pushes to `main` and weekly, and the audit checks every commit on `main`. No finding is suppressed beyond [exceptions](../exceptions.md).
