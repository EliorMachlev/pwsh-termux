# CI / CD

Workflows are in [`.github/workflows/`](../../../.github/workflows). They share these rules:

- **Every action is pinned to a commit SHA** with its version in a trailing comment (`uses: actions/checkout@<sha> # v7.0.1`). Tags can be moved; SHAs cannot. Dependabot proposes updates to both.
- **Least privilege.** `permissions: contents: read` at the top of each workflow; a job asks for more only where it needs it (`security-events: write` for code scanning, `pages: write` + `id-token: write` to deploy, `contents: write` to create release assets).
- **`step-security/harden-runner` first in every job**, in `audit` mode (it records the runner's network use).
- **`persist-credentials: false`** on every checkout, so the token is not left in `.git/config`.
- **Concurrency.** A newer push to a pull request or topic branch cancels a run still going; runs on `main` always finish. Deploys share a `pages` group and are never cancelled.
- **Timeouts** on every job.
- **No `pull_request_target`**, and untrusted event data is never interpolated into a script.

## Workflows

| Workflow | What it does |
|---|---|
| [`build-packages.yaml`](../../../.github/workflows/build-packages.yaml) | **Build, SBOMs and provenance** (reusable, called by `update.yaml`). Finds releases, builds the `.deb` files, writes four SBOMs, attests the lot. No signing key. |
| [`update.yaml`](../../../.github/workflows/update.yaml) | **The pipeline.** Calls `build-packages.yaml`, builds and signs the repository, merges the website, archives each `.deb` with its SBOMs, provenance and the public key as a release, deploys to Pages. Daily, on pushes to `scripts/**`, `docs/**` and itself, and by hand. Refuses to run without `GPG_PRIVATE_KEY`. |
| [`ci.yaml`](../../../.github/workflows/ci.yaml) | `shellcheck` on `scripts/*.sh`; `actionlint` (a release binary checked against a pinned SHA-256 before it runs); a **package build** of the current stable release with checks of the patched loader and the symlink, an unsigned repository, and the site assembly. |
| [`site.yaml`](../../../.github/workflows/site.yaml) | [`site-check.py`](../../../.github/scripts/site-check.py): CSP, no scripts, nothing from another site, local links, sitemap, robots, `security.txt`, `CNAME` ([website](website.md)). |
| [`docs-checks.yaml`](../../../.github/workflows/docs-checks.yaml) | **lychee** (a pinned, checksum-verified release) checks every local link and `#anchor` in the Markdown and pages on each change, and external links weekly; **typos** (hash-pinned) checks spelling. |
| [`zizmor.yaml`](../../../.github/workflows/zizmor.yaml) | Audits the workflows for template injection, over-broad permissions, leftover credentials, unpinned or impostor actions. Every finding goes to code scanning; medium or higher fails the job. zizmor is installed from `.github/zizmor/requirements.txt` with `--require-hashes`. |
| [`codeql.yaml`](../../../.github/workflows/codeql.yaml) | CodeQL for the `actions` language (there is no CodeQL pack for shell). |
| [`gitleaks.yaml`](../../../.github/workflows/gitleaks.yaml) | Scans the whole history for secrets, built from a pinned commit (checked after fetching) and cached. Matches are redacted in the log. |
| [`dependency-review.yaml`](../../../.github/workflows/dependency-review.yaml) | On pull requests, fails on a new dependency with a high-severity advisory. |
| [`scorecard.yaml`](../../../.github/workflows/scorecard.yaml) | OpenSSF Scorecard, published weekly and on pushes; the README badge reads it. |

## Dependabot

[`dependabot.yml`](../../../.github/dependabot.yml) updates, weekly: the pinned GitHub Actions (one grouped pull request), and the two hash-pinned Python requirement files (`.github/zizmor`, `.github/docs-checks`). Every update waits a 7-day cooldown after a release before it is proposed.

## Secrets

One: **`GPG_PRIVATE_KEY`**, the repository's signing key, used only by `update.yaml`'s "Build the signed apt repository" step ([security](security.md#secrets)). `GITHUB_TOKEN` is the workflows' own, scoped per job.

## When a run fails

- **`update.yaml` fails, the site stays as it was.** Nothing is deployed from a failed run.
- **"GPG_PRIVATE_KEY secret is not set"**: the secret is missing; [release](release.md#one-time-setup) says how to add it.
- **Checksum mismatch or "no checksum for …"**: Microsoft's `hashes.sha256` and the tarball disagree, or its format changed. Do not work around it; see [packaging](architecture/packaging.md).
- **`find-releases.sh` finds no stable release**: usually the GitHub API is down or rate limited; re-run.
- **A scheduled workflow stops running**: GitHub disables schedules after 60 days without repository activity; re-enable it in the Actions tab or push a commit.
