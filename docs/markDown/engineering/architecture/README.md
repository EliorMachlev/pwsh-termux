# Architecture

pwsh-termux is a small pipeline, not an application: a few Bash scripts and one workflow that turn Microsoft's releases into a signed apt repository and a website. There is no server and no database; everything is rebuilt from upstream on each run and deployed as static files.

```text
Microsoft's GitHub releases
        │  find-releases.sh     which tags to package
        ▼
official linux-arm64 tarball ──► hashes.sha256 check
        │  build-deb.sh         patch the ELF loader, build the .deb
        ▼
pwsh_<version>_aarch64.deb   +  pwsh-termux-keyring_<version>_all.deb
        │                          (build-keyring.sh, from keys/)
        │  build-repo.sh        key check, apt index + signature
        │  assemble-site.sh     website merged in
        ▼
GitHub Pages artifact ──► https://pwsh-termux.machlev.org/
        └─ each .deb also published as a GitHub release asset
```

| Stage | Script | Reads | Writes | Details |
|---|---|---|---|---|
| Choose releases | [`scripts/find-releases.sh`](../../../../scripts/find-releases.sh) | Microsoft's release list (GitHub API) | `stable <tag>`, `preview <tag>` lines | [releases](releases.md) |
| Build a package | [`scripts/build-deb.sh`](../../../../scripts/build-deb.sh) | the release tarball and its hashes | `<package>_<version>_aarch64.deb` | [packaging](packaging.md) |
| Build the keyring package | [`scripts/build-keyring.sh`](../../../../scripts/build-keyring.sh) | `keys/pwsh-termux-archive-keyring.gpg` | `pwsh-termux-keyring_<version>_all.deb` (reproducible) | [repository](repository.md#the-keyring-package) |
| Check the keys | [`scripts/check-keys.sh`](../../../../scripts/check-keys.sh) | `keys/` | fingerprints; fails on secret or armored keys | [repository](repository.md#signing) |
| Build the repository | [`scripts/build-repo.sh`](../../../../scripts/build-repo.sh) | the `.deb` files, `keys/`, the signing key | `dists/`, `pool/`, public key, `pwsh-termux-keyring.deb` | [repository](repository.md) |
| Add the website | [`scripts/assemble-site.sh`](../../../../scripts/assemble-site.sh) | `docs/` | pages and assets next to the repository | [hosting](hosting.md) |
| Run it all | [`.github/workflows/update.yaml`](../../../../.github/workflows/update.yaml) | | the Pages deployment, release assets | [CI / CD](../ci-cd.md) |

## Rules

These hold across the pipeline; a change that breaks one needs a reason written in the commit.

1. **Verify before use.** Nothing is extracted, patched or packaged from a download whose SHA-256 has not matched Microsoft's `hashes.sha256` for that release.
2. **Patch at build time.** The device receives an already-patched `pwsh`. Packages never depend on `glibc-runner` or `patchelf`, and nothing patches a file at install time.
3. **Never publish unsigned.** `build-repo.sh` skips signing only when `SIGN_KEY` is unset (local tests); the workflow fails without the key instead. It also refuses to sign with a key that is not in `keys/`, the public keys users install.
4. **Stateless.** Each run rebuilds from upstream; the repository's content is a function of Microsoft's current releases and this repository's scripts. No state is kept in Git history (the `.deb` files are 50 MB each).
5. **Fail closed.** `set -euo pipefail` everywhere; an unknown tag format, a missing checksum, a failed patch or a missing signing key stops the run, and the previously deployed site stays as it was.
6. **Same scripts everywhere.** The scripts run unchanged on Termux and on the CI runner, which is why the apt index is generated with `dpkg-deb` and plain shell rather than `apt-ftparchive`, which Termux does not have.
7. **Say what is true.** The package says it is unofficial; the documentation describes what the code does, not what it might.
