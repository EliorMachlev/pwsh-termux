# Contributing

Short version: [CONTRIBUTING.md](../../../CONTRIBUTING.md). This is the full guide.

## What to contribute

- **Bug fixes** to the scripts, the workflows, the website or the docs are welcome as pull requests.
- **New features and refactors:** open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues) first, so the idea can be agreed before the work is done. Things that change what users install (a new package, architecture, suite or channel rule) are decisions for the maintainer.
- **Problems in PowerShell itself** belong to [Microsoft](https://github.com/PowerShell/PowerShell/issues); this project repackages it and does not patch its behavior.

## Setup

Everything runs on Termux or Linux with Bash. You need `bash`, `curl`, `jq`, `python3`, `dpkg-deb` and `patchelf` (on Termux: the glibc one at `$PREFIX/glibc/bin/patchelf`), plus `gnupg` to test signing. [Build](build.md) has the commands and the Termux quirks.

## Branches and commits

- One long-lived branch, `main`; branch from `origin/main` and open a pull request ([branching](branching.md)).
- Title the pull request `type(scope): short description`: `feat`, `fix`, `docs`, `ci`, `build`, `chore`, `deps`, `test`; the scope is the script or area (`build-deb`, `site`, `release`). Example: `fix(build-deb): handle a missing checksum`. Dependabot uses `chore(deps)`.
- Write the description for the person who reads the release notes or the history later: what changed and why.

## Style

- **Bash.** `set -euo pipefail` at the top, quoted expansions, the shared `log`/`die` helpers (they write to stderr), and the other shared constants and helpers in [`scripts/lib/common.sh`](../../../scripts/lib/common.sh) (each script sources it; the repository's `.shellcheckrc` lets shellcheck follow it). Put a helper there when more than one script needs it; a constant goes there only if a helper there uses it. Nothing may need more than Bash, coreutils, `curl`, `jq`, `dpkg-deb`, `patchelf`, `gpg` and `python3`, plus `gh`, `git` and OpenSSH's `ssh-agent` for the scripts that talk to GitHub (the keep-alive and the audit of `main`). `shellcheck --severity=style` must be clean.
- **Python** is for checks only, standard library only, and run with `python3 -I` where it reads untrusted files.
- **Markdown** with sentences that say what the code does. Do not document what it might do.
- **Workflows.** Least privilege (`permissions: contents: read` at the top, more only on the job that needs it), `persist-credentials: false` on checkouts, `step-security/harden-runner` first in each job, and **every action pinned to a commit SHA** with its version in a trailing comment. jactionlint runs at its `pedantic` profile and fails on any finding, so also: `defaults: run: shell: bash`, a fixed runner image (`ubuntu-24.04`), a `name:` on each job, `if: ${{ … }}`, and a comment on each permission beyond `contents: read` ([ci-cd.md](ci-cd.md)). Do not use `pull_request_target`, and do not put untrusted input (`github.event.*`) into a `run:` script; pass it through `env:`.

## No suppressions, no cosmetic workarounds

- **Never add a suppression of any kind**: a `# shellcheck disable=` comment, a `# zizmor: ignore`, an allowlist entry in a scanner's config, a line in a lychee ignore file, a word added to `_typos.toml`, or a disabled rule.
- **Never write a workaround that hides a real issue** just to quiet a tool (a rename or restructure done only so a rule stops matching, excluding a file from a check). If the problem is still there, the warning must be too.
- **Fix the cause.** If there is no real fix yet, leave the warning visible and say what it is and why it can't be fixed now.
- The only suppressions in the tree are the ones in [exceptions.md](exceptions.md). Adding one is the maintainer's decision, not the contributor's.

## Pull request checklist

The [template](../../../.github/pull_request_template.md) is the checklist:

- `shellcheck --shell=bash --severity=style scripts/*.sh scripts/lib/*.sh` is clean.
- `python3 .github/scripts/site-check.py docs` passes.
- A changed script was run locally, and the PR says what you ran.
- Nothing is suppressed beyond [exceptions.md](exceptions.md).
- A new or changed action is pinned to a SHA with its version in a comment.
- A new site page is in `docs/sitemap.xml` and keeps the Content-Security-Policy.
- Docs are updated where the change needs it, in the same PR.

CI ([ci-cd.md](ci-cd.md)) runs the rest: jactionlint, a real package build, CodeQL, zizmor, Gitleaks, and the link and spelling checks.

## Reporting a vulnerability

Don't open a public issue: follow [SECURITY.md](../../../SECURITY.md).
