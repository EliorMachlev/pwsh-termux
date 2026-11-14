# Contributing

Short version: [CONTRIBUTING.md](../../../CONTRIBUTING.md). This is the full guide.

## What to contribute

- **Bug fixes** to the scripts, the workflows, the website or the docs are welcome as pull requests.
- **New features and refactors:** open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues) first, so the idea can be agreed before the work is done. Things that change what users install (a new package, architecture, suite or channel rule) are decisions for the maintainer.
- **Problems in PowerShell itself** belong to [Microsoft](https://github.com/PowerShell/PowerShell/issues); this project repackages it and does not patch its behavior.

## Setup

Everything runs on Termux or Linux with Bash. You need `bash`, `curl`, `jq`, `python3`, `dpkg-deb` and `patchelf` (on Termux: the glibc one at `$PREFIX/glibc/bin/patchelf`), plus `gnupg` to test signing. [Build](build.md) has the commands and the Termux quirks.

## Branches and commits

- One long-lived branch, `main`; branch from `origin/main` and open a pull request ([branching](branching.md)). It merges with *Squash and merge* once its required checks pass ([required status checks](release.md#required-status-checks)); nobody can push to `main` directly. Never put a skip-CI token in a pull request's commit messages: the checks would not run, and the pull request could not merge.
- Title the pull request `type(scope): short description`: `feat`, `fix`, `docs`, `ci`, `build`, `chore`, `deps`, `test`; the scope is the script or area (`build-deb`, `site`, `release`). Example: `fix(build-deb): handle a missing checksum`. Dependabot uses `chore(deps)`.
- Write the description for the person who reads the release notes or the history later: what changed and why.
- **Sign off every commit** ([below](#developer-certificate-of-origin)): `git commit -s`.

## Developer Certificate of Origin

Every commit in a pull request certifies the [Developer Certificate of Origin 1.1](https://developercertificate.org/): that you wrote the change, or otherwise have the right to submit it under the project's [license](../../../LICENSE), and that it may be kept and redistributed as part of the project's public record. You certify it by signing off the commit, with a `Signed-off-by:` trailer that gives your name and e-mail address, as the commit's author:

```text
fix(build-deb): handle a missing checksum

Signed-off-by: Ada Lovelace <ada@example.org>
```

- `git commit -s` (`--signoff`) adds the trailer from your `user.name` and `user.email`, which must be the commit's author. A commit made on GitHub's website gets one by itself (the repository requires it of web commits).
- Forgot? Sign off the pull request's commits and push again: `git rebase --signoff origin/main`, then `git push --force-with-lease`. One commit: `git commit --amend --no-edit -s`. That signs as you: a commit another person wrote needs that person's own sign-off (they amend it with `-s`), or you re-author it with `git commit --amend --reset-author -s` once you have the right to submit it.
- The required check **DCO** ([`dco.yaml`](../../../.github/workflows/dco.yaml), [`check-dco.sh`](../../../scripts/check-dco.sh)) fails a pull request with a commit that lacks the trailer, or whose trailer names someone other than the author (case and spaces aside). The trailer must be in the message's last paragraph, where `git commit -s` puts it. Not checked: merge commits (such as GitHub's *Update branch*), commits already on `main` that reached the branch by merging it in, Dependabot's commits in its own pull requests, and the [keep-alive commit](ci-cd.md#keep-alive-commit).
- The check runs the checker and its tests from the pull request's **base commit**, not from the pull request, so a pull request cannot replace them with ones that always pass; a pull request that changes the checker is judged by the base's copy. Limit: a pull request can still edit `dco.yaml` itself, and the maintainer's review of workflow changes is what catches that.
- **The commits are checked, not the pull request's description.** `main` takes a squash merge, and its message is the pull request's description, so the commit on `main` does not carry the sign-offs; the signed-off commits stay in the pull request (`refs/pull/<n>/head`), linked from the squash commit through its pull request number. Checking the commits means each sign-off is made by `git commit -s` on the work it covers, at the time, rather than a line typed into a description that can still be edited after the check.

## Tests

New behaviour and bug fixes come with an automated test. Shell logic is tested by a `scripts/test-*.sh` script that CI runs ([CI / CD](ci-cd.md)); the Python in `scripts/` is tested with Hypothesis under `tests/fuzz/`. A pull request that changes behaviour without a test needs a reason in its description. The pull request template asks for it, and the required checks must pass before merge.

## Style

- **Bash.** `set -euo pipefail` at the top, quoted expansions, the shared `log`/`die` helpers (they write to stderr), and the other shared constants and helpers in [`scripts/lib/common.sh`](../../../scripts/lib/common.sh) (each script sources it; the repository's `.shellcheckrc` lets shellcheck follow it). Put a helper there when more than one script needs it; a constant goes there only if a helper there uses it. Nothing may need more than Bash, coreutils, `curl`, `jq`, `dpkg-deb`, `patchelf`, `gpg` and `python3`, plus `gh`, `git` and OpenSSH's `ssh-agent` for the scripts that talk to GitHub (the keep-alive and the audit of `main`). `shellcheck --severity=style` must be clean.
- **Python** is for checks only, standard library only, and run with `python3 -I` where it reads untrusted files.
- **Markdown** with sentences that say what the code does. Do not document what it might do.
- **Workflows.** Least privilege (`permissions: contents: read` at the top, more only on the job that needs it), `persist-credentials: false` on checkouts, `step-security/harden-runner` first in each job, and **every action pinned to a commit SHA** with its version in a trailing comment. jactionlint runs at its `pedantic` profile and fails on any finding, so also: `defaults: run: shell: bash`, a fixed runner image (`ubuntu-24.04` or `ubuntu-26.04`, never `ubuntu-latest`), a `name:` on each job, `if: ${{ … }}`, and a comment on each permission beyond `contents: read` ([ci-cd.md](ci-cd.md)). Do not use `pull_request_target`, and do not put untrusted input (`github.event.*`) into a `run:` script; pass it through `env:`.

## No suppressions, no cosmetic workarounds

- **Never add a suppression of any kind**: a `# shellcheck disable=` comment, a `# zizmor: ignore`, an allowlist entry in a scanner's config, a line in a lychee ignore file, a word added to `_typos.toml`, or a disabled rule.
- **Never write a workaround that hides a real issue** just to quiet a tool (a rename or restructure done only so a rule stops matching, excluding a file from a check). If the problem is still there, the warning must be too.
- **Fix the cause.** If there is no real fix yet, leave the warning visible and say what it is and why it can't be fixed now.
- The only suppressions in the tree are the ones in [exceptions.md](exceptions.md). Adding one is the maintainer's decision, not the contributor's.

## Pull request checklist

The [template](../../../.github/pull_request_template.md) is the checklist:

- Every commit is signed off ([DCO](#developer-certificate-of-origin)).
- `shellcheck --shell=bash --severity=style scripts/*.sh scripts/lib/*.sh` is clean.
- `python3 .github/scripts/site-check.py docs` passes.
- A changed script was run locally, and the PR says what you ran.
- Nothing is suppressed beyond [exceptions.md](exceptions.md).
- A new or changed action is pinned to a SHA with its version in a comment.
- A new site page is in `docs/sitemap.xml` and keeps the Content-Security-Policy.
- Docs are updated where the change needs it, in the same PR.

CI ([ci-cd.md](ci-cd.md)) runs the rest: the DCO check, jactionlint, a real package build, CodeQL, zizmor, Gitleaks, the Hypothesis fuzzing of `spdx-build-view.py`, the link and spelling checks, and the HTML and CSS validation (vnu and Stylelint; to run it locally, see [build.md](build.md#check-the-website)).

## Reporting a vulnerability

Don't open a public issue: follow [SECURITY.md](../../../SECURITY.md).
