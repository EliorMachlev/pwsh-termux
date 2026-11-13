# Branches and the pipeline

There is one long-lived branch, **`main`**. It is what the website and the repository are built from.

- Changes arrive by **pull request** from a topic branch off `main`, titled `type(scope): description` ([contributing](contributing.md)).
- **Releases are not branches or tags in this repository.** A new PowerShell release is picked up by the scheduled workflow and published without a commit here ([release](release.md)).
- Nobody pushes straight to `main`, the maintainer included: the ruleset *Main* takes changes only through a pull request whose 13 required checks have passed, merged with *Squash and merge* ([rulesets](release.md#rulesets)). The one exception is the monthly keep-alive commit, pushed with the deploy key ([keep-alive commit](ci-cd.md#keep-alive-commit)).

## Which checks run where

| Workflow | Pull request | Push to `main` | Schedule | Notes |
|---|---|---|---|---|
| [CI](../../../.github/workflows/ci.yaml) (shellcheck, jactionlint, key, keep-alive and audit tests, package build) | yes, every one (required) | yes, when scripts, keys, docs, workflows or `dependabot.yml` change | | builds the real stable package |
| [Site](../../../.github/workflows/site.yaml) (site check, HTML and CSS validation) | yes, every one (required) | yes, for `docs/**`, `art/brand/**`, its checkers and the site scripts | weekly | also catches an expiring `security.txt` |
| [Docs checks](../../../.github/workflows/docs-checks.yaml) | yes, every one (required; local links only) | yes, for the docs | weekly (adds external links) | lychee, typos |
| [Zizmor](../../../.github/workflows/zizmor.yaml) | yes, every one (required) | yes, for workflows | weekly | uploads SARIF to code scanning |
| [CodeQL](../../../.github/workflows/codeql.yaml) | yes, every one (required) | yes, for workflows | weekly | `actions` language |
| [Gitleaks](../../../.github/workflows/gitleaks.yaml) | yes, every one (required) | yes | weekly | whole history |
| [Dependency Review](../../../.github/workflows/dependency-review.yaml) | yes, every one (required) | | | blocks high-severity advisories |
| [OpenSSF Scorecard](../../../.github/workflows/scorecard.yaml) | | yes | weekly | |
| [Update packages](../../../.github/workflows/update.yaml) | | yes, for scripts, docs and itself | **daily** | builds, signs and **deploys**; re-signs daily (Valid-Until) |
| [Index staleness](../../../.github/workflows/staleness.yaml) | | | daily | opens an issue if the live index has under 7 days left |
| [Yearly key review](../../../.github/workflows/key-review.yaml) | | | yearly | opens a reminder issue |

A required check must run on every pull request, so these workflows have no `paths` filter on `pull_request`: a workflow a path filter skips never reports, and the pull request could never merge ([required status checks](release.md#required-status-checks)). The keep-alive dry runs (`keepalive.yaml`, `keepalive-commit.yaml`) still run only when their own files change, and are not required.

Only `update.yaml` publishes anything, and only from `main`. Workflows triggered by a pull request have read-only tokens and no access to the signing key.
