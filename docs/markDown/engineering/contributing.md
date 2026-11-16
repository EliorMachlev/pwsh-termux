# Contributing

Short version: [CONTRIBUTING.md](../../../CONTRIBUTING.md). This is the full guide.

## What to contribute

- **Bug fixes** to the scripts, workflows, website or docs: open a pull request.
- **New features and refactors:** open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues) first. Changes to what users install (a new package, architecture, suite or channel rule) are the maintainer's decision.
- **Problems in PowerShell itself** go to [Microsoft](https://github.com/PowerShell/PowerShell/issues); this project repackages PowerShell and does not patch its behaviour.

## Setup

Termux or Linux with Bash. You need `bash`, `curl`, `jq`, `python3`, `dpkg-deb` and `patchelf` (on Termux, the glibc one at `$PREFIX/glibc/bin/patchelf`), plus `gnupg` to test signing. Commands and Termux quirks: [build](build.md).

## Branches and commits

1. Branch from `origin/main` ([branching](branching.md)); nobody can push to `main` directly.
2. Title the pull request `type(scope): short description`. Types: `feat`, `fix`, `docs`, `ci`, `build`, `chore`, `deps`, `test`; the scope is the script or area (`build-deb`, `site`, `release`). Example: `fix(build-deb): handle a missing checksum`. Dependabot uses `chore(deps)`.
3. Describe what changed and why, for whoever reads the history later.
4. Sign off every commit with `git commit -s` ([below](#developer-certificate-of-origin)).
5. Never put a skip-CI token in a commit message: the required checks would not run and the pull request could not merge.
6. The pull request merges with *Squash and merge* once its [required checks](ci-cd/rulesets.md#required-status-checks) pass.

## Developer Certificate of Origin

Each commit in a pull request certifies the [Developer Certificate of Origin 1.1](https://developercertificate.org/): you wrote the change, or have the right to submit it under the project's [license](../../../LICENSE), and it may be redistributed as part of the project's public record. Certify it with a `Signed-off-by:` trailer naming the commit's author:

```text
fix(build-deb): handle a missing checksum

Signed-off-by: Ada Lovelace <ada@example.org>
```

- `git commit -s` adds the trailer from your `user.name` and `user.email`, which must match the commit's author. A commit made on GitHub's website gets one automatically (the repository requires it).
- **Forgot?** `git rebase --signoff origin/main`, then `git push --force-with-lease`; for one commit, `git commit --amend --no-edit -s`. That signs as you: someone else's commit needs their own sign-off, or you re-author it with `git commit --amend --reset-author -s` once you have the right to submit it.
- The required check **DCO** ([`dco.yaml`](../../../.github/workflows/dco.yaml), [`check-dco.sh`](../../../scripts/check-dco.sh)) fails a commit without the trailer, or whose trailer names someone other than the author (case and surrounding spaces ignored). The trailer must be in the message's last paragraph.
- Not checked: merge commits (such as *Update branch*), commits already on `main`, Dependabot's commits in its own pull requests, and the [keep-alive commit](ci-cd/keepalive.md#keep-alive-commit).
- The check runs the checker and its tests from the pull request's **base commit**, so a pull request cannot replace them. A pull request can still edit `dco.yaml` itself; the maintainer's review of workflow changes catches that.
- **Commits are checked, not the description.** The squash commit on `main` takes the pull request's description and does not carry the sign-offs; the signed-off commits stay in `refs/pull/<n>/head`, linked by the pull request number.

## Tests

New behaviour and bug fixes come with an automated test; a pull request without one says why.

- Shell logic: a `scripts/test-*.sh` script. Python in `scripts/`: Hypothesis tests under `tests/fuzz/`.
- Every script in `scripts/` has a test, and tests run offline: stubs stand in for `curl`, `gh` and the SBOM tools, fixtures go to a temporary folder, and local git repositories stand in for GitHub.
- A refusal is checked for its reason, not only for failing. A bug fix adds a test that fails without the fix.
- A new test script is named `scripts/test-<name>.sh` and gets a step in a job in `ci.yaml`; the `Coverage` job runs every `scripts/test-*.sh` on its own.

The `Coverage` check measures how much of `scripts/` the tests run: in Bash, the lines that start a command (traced with xtrace); in Python, statements (coverage.py). It fails when Bash, Python or the total drops below its floor (`COVERAGE_MIN_*` in `ci.yaml`). When your tests raise coverage, raise the floors to the new values, rounded down; never lower them. To list uncovered lines (needs [shfmt](https://github.com/mvdan/sh): `pkg install shfmt`; and, for the Python, coverage.py and Hypothesis: `pip install coverage hypothesis`):

```bash
rm -rf out/trace
for t in scripts/test-*.sh; do python3 .github/scripts/coverage.py run out/trace -- bash "$t"; done
COVERAGE_FILE=out/python.coverage python3 -m coverage run --include='scripts/*.py' -m unittest discover -s tests/fuzz
COVERAGE_FILE=out/python.coverage python3 -m coverage json -o out/python-coverage.json
python3 .github/scripts/coverage.py report out/trace --python-json out/python-coverage.json
```

`test-validate-site.sh` needs the path to `vnu.jar` ([build](build.md#check-the-website)); without it, `validate-site.sh` shows as not run.

## Style

- **Bash.** `set -euo pipefail`, quoted expansions, and the shared `log`/`die` helpers and constants in [`scripts/lib/common.sh`](../../../scripts/lib/common.sh), which every script sources. A helper goes there when more than one script needs it; a constant only if a helper there uses it. Allowed tools: Bash, coreutils, `curl`, `jq`, `dpkg-deb`, `patchelf`, `gpg`, `python3`, plus `gh`, `git` and `ssh-agent` for the scripts that talk to GitHub. `shellcheck --severity=style` must be clean.
- **Python** is for checks only: standard library only, run with `python3 -I` where it reads untrusted files.
- **Markdown** says what the code does, not what it might do.
- **Workflows.**
  - Least privilege: `permissions: contents: read` at the top, more only on the job that needs it, with a comment on each extra permission.
  - `persist-credentials: false` on checkouts; `step-security/harden-runner` first in each job.
  - Every action pinned to a commit SHA, its version in a trailing comment.
  - jactionlint runs at `pedantic` and fails on any finding: `defaults: run: shell: bash`, a fixed runner image (`ubuntu-24.04` or `ubuntu-26.04`, never `ubuntu-latest`), a `name:` on each job, `if: ${{ … }}` ([CI / CD](ci-cd.md)).
  - No `pull_request_target`; untrusted input (`github.event.*`) goes through `env:`, never straight into `run:`.

## No suppressions, no cosmetic workarounds

- **Never add a suppression**: a `# shellcheck disable=`, a `# zizmor: ignore`, a scanner allowlist entry, a lychee ignore line, a word in `_typos.toml`, or a disabled rule.
- **Never hide a real issue** to quiet a tool (a rename or restructure only so a rule stops matching, excluding a file from a check). If the problem remains, so does the warning.
- **Fix the cause.** If there is no fix yet, leave the warning visible and explain what it is and why.
- The only suppressions are those in [exceptions.md](exceptions.md); adding one is the maintainer's decision.

## Pull request checklist

The [template](../../../.github/pull_request_template.md) is the checklist:

1. Every commit is signed off ([DCO](#developer-certificate-of-origin)).
2. A changed script was run locally, and the pull request says what you ran.
3. A changed `build-deb.sh` was run on a device ([build](build.md#testing-on-a-device)).
4. A change to packaging, releases, the repository, keys or the site assembly ran the matching offline tests: `test-build-deb.sh`, `test-find-releases.sh`, `test-make-sboms.sh`, `test-assemble-site.sh`, `test-keys.sh`, `test-release-tags.sh`, `test-keepalive.sh`, `test-dco.sh`; the keyring still builds byte-identical ([build](build.md#build-the-keyring-package)).
5. Changed behaviour or a bug fix comes with a test, or the pull request says why not.
6. Nothing is suppressed beyond [exceptions.md](exceptions.md).
7. A new or changed action is pinned to a SHA with its version in a comment.
8. A new site page is in `docs/sitemap.xml`; the Content-Security-Policy is kept (no scripts, inline `style`, forms or third-party loads).
9. A site change meets the [accessibility rules](website.md#accessibility-rules-for-changes) (WCAG 2.2 AA) and keeps the [accessibility statement](../legal/accessibility-statement.md) true.
10. A changed diagram step updates `gen.mjs`, the GIFs, the Mermaid blocks and the `<ol>` lists together ([build](build.md#regenerate-the-diagrams)).
11. Docs are updated in the same pull request.

CI runs shellcheck, `site-check.py`, the HTML and CSS validation, Stylelint and the axe accessibility check ([CI / CD](ci-cd.md)); fix what it reports. To run them locally, see [build](build.md#check-the-website). The items above are the ones only you can check.

## Reporting a vulnerability

Don't open a public issue: follow [SECURITY.md](../../../SECURITY.md).
