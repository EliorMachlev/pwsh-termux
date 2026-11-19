# Architecture

pwsh-termux is a pipeline, not an application: a few Bash scripts and one workflow turn Microsoft's releases into a signed apt repository and a website. No server, no database: each run rebuilds everything from upstream and deploys static files.

```text
Microsoft's GitHub releases
        │  find-releases.sh     which tags to package
        ▼
official linux-arm64 tarball ──► hashes.sha256 check
        │  build-deb.sh         patch the ELF loader, build the .deb
        ▼
pwsh_<version>_aarch64.deb   +  pwsh-termux-keyring_<version>_all.deb
        │                          (build-keyring.sh, from keys/)
        │  build-repo.sh        key check, unsigned apt index
        │  sign-release.sh      checks the index, signs it (no .deb)
        │  assemble-site.sh     website merged in
        ▼
GitHub Pages artifact ──► https://pwsh-termux.machlev.org/
        └─ each .deb also published as a GitHub release asset
```

## Stages

1. **Choose releases**: [`find-releases.sh`](../../../../scripts/find-releases.sh) prints `stable <tag>` and maybe `preview <tag>` ([releases](releases.md)).
2. **Build each package**: [`build-deb.sh`](../../../../scripts/build-deb.sh) turns a verified tarball into `<package>_<version>_aarch64.deb` ([packaging](packaging.md)).
3. **Build the keyring package**: [`build-keyring.sh`](../../../../scripts/build-keyring.sh) packs `keys/` into `pwsh-termux-keyring_<version>_all.deb`, reproducibly ([keyring](keyring.md)).
4. **Check the keys and the keyring's provenance**: [`check-keys.sh`](../../../../scripts/check-keys.sh) and [`verify-attestation.sh`](../../../../scripts/verify-attestation.sh) ([signing](signing.md)).
5. **Build and sign the repository**: [`build-repo.sh`](../../../../scripts/build-repo.sh) writes `dists/`, `pool/`, the public key and the keyring package, unsigned; [`sign-release.sh`](../../../../scripts/sign-release.sh) signs the index in a job with no `.deb` ([repository](repository.md), [signing](signing.md)).
6. **Add the website**: [`assemble-site.sh`](../../../../scripts/assemble-site.sh) merges `docs/` in ([hosting](hosting.md)).
7. **Run it all**: [`update.yaml`](../../../../.github/workflows/update.yaml) deploys to Pages and creates the release assets ([CI / CD](../ci-cd.md)).

Recovery from a lost or compromised online key is a separate path: the maintainer signs offline with [`recovery-sign.sh`](../../../../scripts/recovery-sign.sh), and `recover.yaml` deploys what [`verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) verifies ([signing](signing.md#rotation-and-recovery)).

## Rules

A change that breaks one of these needs a reason in the commit.

1. **Verify before use.** Nothing is extracted, patched or packaged from a download whose SHA-256 does not match Microsoft's `hashes.sha256` for that release.
2. **Patch at build time.** The device gets an already-patched `pwsh`. Packages never depend on `glibc-runner` or `patchelf`, and nothing is patched at install time.
3. **Never publish unsigned.** `build-repo.sh` never signs; the `sign` job fails without the key. `sign-release.sh` refuses to sign with any key but the one in `keys/`, or an index with a package whose provenance did not verify.
4. **Stateless.** Each run rebuilds from upstream; no state is kept in Git (each `.deb` is about 50 MB).
5. **Fail closed.** `set -euo pipefail` everywhere; an unknown tag format, a missing checksum, a failed patch or a missing key stops the run, and the deployed site stays as it was.
6. **Same scripts everywhere.** They run unchanged on Termux and on the CI runner, so the apt index is written with `dpkg-deb` and shell, not `apt-ftparchive` (Termux lacks it).
7. **Say what is true.** The package says it is unofficial; the docs describe what the code does.
