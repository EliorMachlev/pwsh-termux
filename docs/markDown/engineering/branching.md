# Branches and the pipeline

There is one long-lived branch, **`main`**. It is what the website and the repository are built from.

- Changes arrive by **pull request** from a topic branch off `main`, titled `type(scope): description` ([contributing](contributing.md)).
- **Releases are not branches or tags in this repository.** A new PowerShell release is picked up by the scheduled workflow and published without a commit here ([release](release.md)).
- The maintainer may push small fixes straight to `main`; branch protection is not enabled, so the checks below run after the push in that case rather than gating it.

## Which checks run where

| Workflow | Pull request | Push to `main` | Schedule | Notes |
|---|---|---|---|---|
| [CI](../../../.github/workflows/ci.yaml) (shellcheck, actionlint, package build) | yes, when scripts, docs or workflows change | yes | | builds the real stable package |
| [Site](../../../.github/workflows/site.yaml) | yes, for `docs/**` | yes | weekly | also catches an expiring `security.txt` |
| [Docs checks](../../../.github/workflows/docs-checks.yaml) | yes | yes | weekly (adds external links) | lychee, typos |
| [Zizmor](../../../.github/workflows/zizmor.yaml) | yes, for workflows | yes | weekly | uploads SARIF to code scanning |
| [CodeQL](../../../.github/workflows/codeql.yaml) | yes, for workflows | yes | weekly | `actions` language |
| [Gitleaks](../../../.github/workflows/gitleaks.yaml) | yes | yes | weekly | whole history |
| [Dependency Review](../../../.github/workflows/dependency-review.yaml) | yes | | | blocks high-severity advisories |
| [OpenSSF Scorecard](../../../.github/workflows/scorecard.yaml) | | yes | weekly | |
| [Update packages](../../../.github/workflows/update.yaml) | | yes, for scripts, docs and itself | **daily** | builds, signs and **deploys** |

Only `update.yaml` publishes anything, and only from `main`. Workflows triggered by a pull request have read-only tokens and no access to the signing key.
