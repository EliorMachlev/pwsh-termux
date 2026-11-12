# Repo instructions for Claude Code

Read the project docs before making changes. Contributor rules (branching, code style, the PR checklist, commit conventions) live in [`docs/markDown/engineering/contributing.md`](docs/markDown/engineering/contributing.md).

Other reference docs are in [`docs/markDown/`](docs/markDown/README.md) (index there):

- [`engineering/architecture/`](docs/markDown/engineering/architecture/README.md): the pipeline stage by stage (releases, packaging, repository, hosting)
- [`engineering/build.md`](docs/markDown/engineering/build.md): building and testing locally, including the Termux quirks
- [`engineering/release.md`](docs/markDown/engineering/release.md): how releases happen, one-time setup, key rotation
- [`product/packages.md`](docs/markDown/product/packages.md): what the packages are and how versions map
- [`engineering/ci-cd.md`](docs/markDown/engineering/ci-cd.md): workflows, permissions, pinning
- [`engineering/security.md`](docs/markDown/engineering/security.md): security posture
- [`engineering/exceptions.md`](docs/markDown/engineering/exceptions.md): the only suppressions allowed, and why
- [`engineering/website.md`](docs/markDown/engineering/website.md): the GitHub Pages site and its checks

Follow the guidance in those files. If a docs update is needed, edit the relevant `.md` there.

## Things that are easy to get wrong

- **Never publish an unsigned repository.** `scripts/build-repo.sh` only skips signing when `SIGN_KEY` is unset, which is for local tests; the workflow refuses to run without the `GPG_PRIVATE_KEY` secret.
- **Never print, commit or copy the signing key.** The secret and its backups are not for logs, the repo, the website or an artifact. Do not add steps that write it to `GITHUB_ENV` or an output.
- **Verify before you build.** Nothing is built from a download that has not matched Microsoft's `hashes.sha256` (a UTF-16 file: decode it, don't `grep` it).
- **Patch at build time, not on the device.** Packages must ship an already-patched `pwsh` and must not depend on `glibc-runner` or `patchelf`.
- **Pin every action to a commit SHA**, with its version in a trailing comment (`uses: owner/repo@<sha> # vX.Y.Z`). Dependabot updates both.
- **Keep the website free of scripts and third-party loads.** Each page's Content-Security-Policy `<meta>` allows only the site itself; `.github/scripts/site-check.py` enforces it. A new page goes into `docs/sitemap.xml`.
- **Do not claim what the repo does not do.** The docs describe the implementation; if you change behavior, change the doc in the same commit.

## Working in Termux

This project is developed on a phone, in Termux:

- There is no `/usr/bin/env`: run scripts as `bash scripts/<name>.sh`, not `./scripts/<name>.sh`.
- The default `umask` is 077. `build-deb.sh` sets its own `umask 022`; do the same in any new script that creates packaged files.
- Use the glibc `patchelf`: `PATCHELF=$PREFIX/glibc/bin/patchelf`.
- `dpkg-scanpackages` and `apt-ftparchive` are not available; the repository index is generated with `dpkg-deb -f` on purpose, so the same script runs on Termux and on CI.

## No suppressions, no cosmetic workarounds

Full rule: [`contributing.md`](docs/markDown/engineering/contributing.md#no-suppressions-no-cosmetic-workarounds).

- **Never add a suppression of any kind**: a `# shellcheck disable=` comment, a `# zizmor: ignore`, a `# nosemgrep`, an `allowlist` entry in a scanner config, a `.lycheeignore` line, a word added to `_typos.toml`, or a disabled rule.
- **Never write a workaround that hides a real issue** just to quiet a linter (a rename or restructure done only so a rule stops matching, excluding a file from a check). If the problem is still there, the warning must be too.
- **Fix the cause instead.** If there is no real fix yet, leave the warning visible and tell the user what it is and why it can't be fixed now.
- The only suppressions in the tree are those recorded in [`exceptions.md`](docs/markDown/engineering/exceptions.md). Never add an exception on your own: it is the user's decision.

## CI

Don't wait for slow workflows when nothing depends on them; carry on with the next task. The `package` job in CI downloads and builds the real PowerShell package, so it takes a few minutes. A PR is not ready until CI is green.
