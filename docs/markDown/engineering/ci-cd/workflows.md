# CI / CD: workflows

Part of the [CI / CD](../ci-cd.md) docs. All are in [`.github/workflows/`](../../../../.github/workflows). Which run on pull requests, on `main` and on a schedule: [branching](../branching.md#which-checks-run-where).

## Build and publish

- [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml): **build, SBOMs and provenance** (reusable, called by `update.yaml`). Finds releases, builds `pwsh`, `pwsh-preview` and `pwsh-termux-keyring` (from `keys/`), writes four SBOMs per package and attests them. No signing key ([provenance](../release/provenance.md)).
- [`update.yaml`](../../../../.github/workflows/update.yaml): **the pipeline** ([release](../release.md#what-happens-on-a-run)).
  - Jobs: `build` (calls `build-packages.yaml`); `verify` (read-only, no key) checks the keyring package's provenance with `scripts/verify-attestation.sh`; `publish` (environment `signing`) builds and signs the repository, merges the website, signs and pushes the [release tags](../release/tags.md), creates the releases (`gh release create --verify-tag`, once, never modified, so [immutable releases](../release/setup.md#steps) can be on); `deploy` to Pages; `keepalive` (`actions: write` only, [keep-alive](keepalive.md#schedule-keep-alive)).
  - `publish` refuses a signing key that is not the key in `keys/`, and a keyring package that is not the verified file or does not ship `keys/`. It refuses to run without `GPG_PRIVATE_KEY`, and warns when `GPG_PASSPHRASE` is not set (which should not happen: the key is protected).
  - Runs daily (re-signing the index without a commit, release or not), on pushes to `scripts/**`, `keys/**`, `docs/**`, `build-packages.yaml` and itself, and by hand.
- [`recover.yaml`](../../../../.github/workflows/recover.yaml): **only after a lost or compromised online key**, by hand with a `recovery-*` release tag. Deploys a repository the maintainer signed offline with the recovery key, after `verify-recovery-repo.sh` checks it against the recovery key alone. Holds no signing key; key files and site come from the commit ([recovery](../release/signing-keys.md#recovery-with-the-offline-key)).

## Tests and checks on pull requests

- [`ci.yaml`](../../../../.github/workflows/ci.yaml): shellcheck, jactionlint, key and release-tag tests, keep-alive and audit tests, packaging script tests, coverage, and a real package build ([what they cover](tests.md)).
- [`site.yaml`](../../../../.github/workflows/site.yaml) ([website](../website.md#the-checks)):
  - **Check the website**: [`site-check.py`](../../../../.github/scripts/site-check.py): CSP, no scripts, nothing from another site, local links, sitemap, robots, `security.txt`, `CNAME`.
  - **Validate the HTML and CSS**: [`test-validate-site.sh`](../../../../scripts/test-validate-site.sh) first, then the W3C Nu Html Checker (vnu) through [`validate-site.sh`](../../../../scripts/validate-site.sh) on every page, the stylesheet and the SVGs of `docs/`, of the site as deployed (assembled around an unsigned repository with a stand-in `pwsh` package, so the generated blocks are filled) and of `art/brand/`, failing on any error, warning or info. Then Stylelint with `stylelint-config-standard` on the stylesheet, as committed and as deployed. vnu, Stylelint and the config come from [`tools/site-lint/`](../../../../tools/site-lint).
  - **Accessibility (WCAG 2.2)**: [`axe-check.mjs`](../../../../tools/site-lint/axe-check.mjs) runs axe-core in headless Chrome on every page of `docs/` and of the assembled site, in light and dark, with and without reduced motion, at desktop and 320 px width. Any WCAG 2.2 level A or AA violation, sideways scrolling at 320 px or a diagram without its pause checkbox fails.
  - The *Check the website* job also compiles `site-check.py` (`py_compile`).
- [`docs-checks.yaml`](../../../../.github/workflows/docs-checks.yaml): **lychee** (pinned, checksum-verified) checks every local link and `#anchor` in the Markdown and pages on every pull request and on docs pushes to `main`, and external links weekly; **typos** (hash-pinned) checks spelling.
- [`zizmor.yaml`](../../../../.github/workflows/zizmor.yaml): audits the workflows for template injection, over-broad permissions, leftover credentials, unpinned or impostor actions. Every finding goes to code scanning; medium or higher fails the job. Installed from `tools/zizmor/requirements.txt` with `--require-hashes`.
- [`codeql.yaml`](../../../../.github/workflows/codeql.yaml): CodeQL for the `actions` language (there is no CodeQL pack for shell).
- [`gitleaks.yaml`](../../../../.github/workflows/gitleaks.yaml): scans the whole history for secrets; built from a pinned commit (checked after fetching) and cached; matches are redacted in the log.
- [`fuzz.yaml`](../../../../.github/workflows/fuzz.yaml): Hypothesis fuzzing of `spdx-build-view.py` ([fuzzing](tests.md#fuzzing)).
- [`dependency-review.yaml`](../../../../.github/workflows/dependency-review.yaml): fails on a new dependency with a high-severity advisory.
- [`dco.yaml`](../../../../.github/workflows/dco.yaml): every commit a pull request adds must carry its author's `Signed-off-by:` ([DCO](tests.md#dco)).
- [`scorecard.yaml`](../../../../.github/workflows/scorecard.yaml): OpenSSF Scorecard, weekly and on pushes to `main`; the README badge reads it.

## Scheduled watchdogs

- [`staleness.yaml`](../../../../.github/workflows/staleness.yaml): **daily** (and by hand).
  - Fetches the live `https://pwsh-termux.machlev.org/dists/stable/InRelease`, verifies it against `keys/`, and checks that at least 7 days are left before `Valid-Until` ([`check-index-freshness.sh`](../../../../scripts/check-index-freshness.sh)).
  - Checks with `keep-schedules-alive.sh check` that GitHub has not disabled a scheduled workflow for inactivity, and prints how many days ago `main` last had a commit.
  - Each problem has one issue, *The live apt index is stale or unreachable* or *A scheduled workflow is disabled*: opened, or commented on if open (never a second), closed with a comment when healthy; the job then fails. A second job renews the schedules ([keep-alive](keepalive.md#schedule-keep-alive)).
  - `issues: write` and `actions: read` on the check, `actions: write` on the keep-alive job.
- [`keepalive.yaml`](../../../../.github/workflows/keepalive.yaml): **Sundays and Wednesdays** (and by hand), renews every scheduled workflow, the third [keep-alive](keepalive.md#schedule-keep-alive) leg. On pull requests touching it or its script, a `--dry-run` with `actions: read`. `actions: write` on the scheduled job only.
- [`keepalive-commit.yaml`](../../../../.github/workflows/keepalive-commit.yaml): **Mondays** (and by hand), pushes a [keep-alive commit](keepalive.md#keep-alive-commit) if `main` has been quiet for 30 days. `contents: read` and `statuses: write` only; refuses any ref but `main`. On pull requests touching it or its script, a dry run over https with no environment and no key.
- [`audit-main.yaml`](../../../../.github/workflows/audit-main.yaml): on every push to `main`, **daily** and by hand, the [audit of main](audit.md).
- [`key-review.yaml`](../../../../.github/workflows/key-review.yaml): every 2 January (and by hand), a *Yearly key review* issue: a checklist for the recovery-key backup, the revocation certificates, the fingerprints and the rotation plan. No key material; one issue per year. `issues: write` only.
- [`renew-security-txt.yaml`](../../../../.github/workflows/renew-security-txt.yaml): on the 1st of each month, if `security.txt`'s `Expires` is under four months away, opens (or comments on) *Renew security.txt* with the command that moves it, and fails; closes it once the date is far enough ahead. It cannot commit the date itself: the rulesets refuse every push made with `GITHUB_TOKEN` ([website](../website.md#updating-securitytxt)).
