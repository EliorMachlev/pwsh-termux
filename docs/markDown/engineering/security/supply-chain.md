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
- Dependabot updates the actions, the pinned Python tools (zizmor, typos, Hypothesis, coverage.py) the site's npm checkers and the ClusterFuzzLite base image; Dependency Review runs on pull requests.
- harden-runner runs first in each job, in `block` mode with a per-job `allowed-endpoints` list (two jobs, `Scorecard analysis` and `Links (lychee)`, stay in `audit` mode and show unexpected egress in the run's insights). The jobs that hold secrets (`sign`, keep-alive commit) run it in `block` mode with a GitHub-only `allowed-endpoints` list; `sign` receives only small files (a job output), never a `.deb` or artifact storage access, so it needs no storage endpoint. `publish`, whose token can write releases, also blocks, but must allow the artifact storage, as must `verify` and `assemble` (artifact download). `verify` also allows `tuf-repo-cdn.sigstore.dev` and `tuf-repo.github.com`: `gh attestation verify` fetches the Sigstore and GitHub trust roots from them, and fails without them. The `gitleaks` job also allows the Go module proxy and checksum database, used when it builds gitleaks on a cache miss. `deploy` (Pages, no key, no `.deb`) blocks too, with the GitHub-only list; it passes the artifact id to GitHub and needs no storage endpoint.

## Network

The pipeline contacts only GitHub: the API, the release downloads, Pages and the Actions services. The website loads nothing from another origin ([website](../website.md)).

## Code analysis

On every change: shellcheck, jactionlint, zizmor, CodeQL (`actions`), Gitleaks, Betterleaks, TruffleHog, lychee, typos, Dependency Review, Hypothesis fuzzing of `spdx-build-view.py`, test coverage with a floor, and a real package build. OpenSSF Scorecard runs on pushes to `main` and weekly, and the audit checks every commit on `main`. No finding is suppressed beyond [exceptions](../exceptions.md).
