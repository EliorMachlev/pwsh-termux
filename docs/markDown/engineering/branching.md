# Branches and the pipeline

There is one long-lived branch, **`main`**. The website and the repository are built from it.

- Changes arrive by **pull request** from a topic branch off `main`, titled `type(scope): description` ([contributing](contributing.md)).
- **Releases are not branches or tags in this repository.** The scheduled workflow picks up a new PowerShell release and publishes it without a commit here ([release](release.md)).
- Nobody pushes straight to `main`, the maintainer included: the ruleset *Main* takes changes only through a pull request whose 19 required checks have passed, merged with *Squash and merge* ([rulesets](ci-cd/rulesets.md)). The one exception is the monthly keep-alive commit, pushed with the deploy key ([keep-alive commit](ci-cd/keepalive.md#keep-alive-commit)).

## Which checks run where

**On every pull request (required):**

1. [CI](../../../.github/workflows/ci.yaml): shellcheck, jactionlint, key, keep-alive and audit tests, packaging script tests, coverage, and a build of the real stable package.
2. [Site](../../../.github/workflows/site.yaml): site check, HTML and CSS validation.
3. [Docs checks](../../../.github/workflows/docs-checks.yaml): lychee (local links only) and typos.
4. [Zizmor](../../../.github/workflows/zizmor.yaml), uploading SARIF to code scanning.
5. [CodeQL](../../../.github/workflows/codeql.yaml), `actions` language.
6. [Gitleaks](../../../.github/workflows/gitleaks.yaml), whole history.
7. [Fuzz](../../../.github/workflows/fuzz.yaml): Hypothesis on `spdx-build-view.py`.
8. [Dependency Review](../../../.github/workflows/dependency-review.yaml): blocks high-severity advisories.
9. [DCO](../../../.github/workflows/dco.yaml): a sign-off on every commit.

Plus the CodeRabbit review. These workflows have no `paths` filter on `pull_request`: a workflow a path filter skips never reports, and the pull request could never merge ([required status checks](ci-cd/rulesets.md#required-status-checks)). The keep-alive dry runs (`keepalive.yaml`, `keepalive-commit.yaml`) run only when their own files change, and are not required.

**On push to `main`:**

1. CI, when the scripts, keys, `SECURITY.md`, docs, workflows, tests, tooling or `dependabot.yml` change.
2. Site, for `docs/**`, `art/brand/**`, its checkers and the site scripts.
3. Docs checks, for the docs.
4. Zizmor and CodeQL, for the workflows.
5. Gitleaks, Fuzz, OpenSSF Scorecard and the [audit of main](ci-cd/audit.md), on every push.
6. [Update packages](../../../.github/workflows/update.yaml), for scripts, keys, docs and its own workflows: builds, signs and **deploys**.

**On a schedule:**

1. Daily: Update packages (re-signs the index for `Valid-Until`), [index staleness](../../../.github/workflows/staleness.yaml) (an issue if the live index has under 7 days left) and the audit of main.
2. Weekly: Site (also catches an expiring `security.txt`), Docs checks (adds external links), Zizmor, CodeQL, Gitleaks, Fuzz (a longer run), Scorecard.
3. Keep-alive: `keepalive.yaml` twice a week, `keepalive-commit.yaml` on Mondays ([keep-alive](ci-cd/keepalive.md)).
4. Monthly: `renew-security-txt.yaml`. Yearly: the [key review](../../../.github/workflows/key-review.yaml) reminder issue.

Only `update.yaml` publishes anything, and only from `main`. Workflows triggered by a pull request have read-only tokens and no access to the signing key.
