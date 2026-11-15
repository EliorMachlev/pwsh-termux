# Repo instructions for Claude Code

Read the project docs before making changes. Contributor rules (branching, style, PR checklist, commits): [`docs/markDown/engineering/contributing.md`](docs/markDown/engineering/contributing.md). The rest is indexed in [`docs/markDown/`](docs/markDown/README.md):

- [`engineering/architecture/`](docs/markDown/engineering/architecture/README.md): the pipeline stage by stage
- [`engineering/build.md`](docs/markDown/engineering/build.md): building and testing locally, Termux quirks
- [`engineering/release.md`](docs/markDown/engineering/release.md): releases, one-time setup, key rotation
- [`product/packages.md`](docs/markDown/product/packages.md): the packages and how versions map
- [`engineering/ci-cd.md`](docs/markDown/engineering/ci-cd.md): workflows, permissions, pinning
- [`engineering/security.md`](docs/markDown/engineering/security.md): security posture, split into [threat model](docs/markDown/engineering/security/threat-model.md), [assurance case](docs/markDown/engineering/security/assurance-case.md) and [supply chain](docs/markDown/engineering/security/supply-chain.md)
- [`engineering/exceptions.md`](docs/markDown/engineering/exceptions.md): the only suppressions allowed
- [`engineering/website.md`](docs/markDown/engineering/website.md): the GitHub Pages site and its checks

If behaviour changes, update the relevant doc in the same commit.

## Easy to get wrong

- **Never publish an unsigned repository.** `scripts/build-repo.sh` skips signing only when `SIGN_KEY` is unset (local tests); the workflow refuses to run without `GPG_PRIVATE_KEY`.
- **`keys/` holds the online signing key plus only what a marker names.** `keys/pwsh-termux-archive-keyring.gpg` is what users trust (shipped in `pwsh-termux-keyring` and as `/pwsh-termux.gpg`): exactly one online key, the signer; the recovery key only if `keys/RECOVERY` names it; a next online key only while `keys/ROTATION` names it. `check-keys.sh`, CI and the publish job refuse anything else, refuse the recovery key as a signer, and refuse a keyring package whose provenance does not verify. Change `keys/` and `GPG_PRIVATE_KEY` only as [release.md](docs/markDown/engineering/release.md#rotating-the-signing-key) says. `KEYRING_FILE` is for tests only; never set it in a publishing workflow.
- **The recovery key never goes near GitHub or CI**, and an agent must never generate it: only the maintainer creates it, offline.
- **Never print, commit or copy the signing key** or its backups (logs, repo, website, artifacts, `GITHUB_ENV`, step outputs).
- **Verify before you build.** Nothing is built from a download that has not matched Microsoft's `hashes.sha256` (UTF-16: decode it, don't `grep` it).
- **Patch at build time, not on the device.** Packages ship an already-patched `pwsh` and do not depend on `glibc-runner` or `patchelf`.
- **Pin every action to a commit SHA** with its version in a trailing comment (`uses: owner/repo@<sha> # vX.Y.Z`).
- **No scripts or third-party loads on the website.** Each page's Content-Security-Policy allows only the site itself (`.github/scripts/site-check.py` enforces it). A new page goes into `docs/sitemap.xml`.
- **Don't claim what the repo does not do.** Docs describe the implementation.

## Working in Termux

- No `/usr/bin/env`: run `bash scripts/<name>.sh`, not `./scripts/<name>.sh`.
- The default `umask` is 077. `build-deb.sh` sets `umask 022`; do the same in any new script that creates packaged files.
- Use the glibc `patchelf`: `PATCHELF=$PREFIX/glibc/bin/patchelf`.
- `dpkg-scanpackages` and `apt-ftparchive` are missing; the index is built with `dpkg-deb -f` on purpose, so the same script runs on Termux and CI.

## No suppressions, no cosmetic workarounds

Full rule: [`contributing.md`](docs/markDown/engineering/contributing.md#no-suppressions-no-cosmetic-workarounds).

- **Never add a suppression**: `# shellcheck disable=`, `# zizmor: ignore`, `# nosemgrep`, a scanner `allowlist` entry, a `.lycheeignore` line, a word in `_typos.toml`, or a disabled rule.
- **Never hide a real issue** to quiet a linter (a rename or restructure only so a rule stops matching, excluding a file from a check).
- **Fix the cause.** If there is no fix yet, leave the warning visible and tell the user what it is and why.
- The only suppressions are in [`exceptions.md`](docs/markDown/engineering/exceptions.md). Never add one yourself: it is the user's decision.

## CI

A PR is not ready until CI is green. Don't wait on slow workflows when nothing depends on them; the `package` job builds the real PowerShell package and takes a few minutes.
