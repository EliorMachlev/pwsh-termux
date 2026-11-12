# The apt repository

[`scripts/build-repo.sh`](../../../../scripts/build-repo.sh) assembles a repository from a folder of `.deb` files:

```bash
SIGN_KEY=<fingerprint> bash scripts/build-repo.sh debs repo
```

## Layout

One suite, one component, one architecture:

```text
repo/
├── dists/stable/
│   ├── Release            index of the index files, with SHA-256 sums
│   ├── InRelease          Release, clear-signed
│   ├── Release.gpg        Release, detached signature
│   └── main/binary-aarch64/
│       └── Packages, Packages.gz, Packages.xz
├── pool/main/<package>/<package>_<version>_aarch64.deb
├── pwsh-termux.gpg        the public key, binary (what apt wants)
└── pwsh-termux.asc        the public key, armored
```

Clients use `deb https://pwsh-termux.machlev.org stable main`.

## The index without apt tooling

Termux has neither `dpkg-scanpackages` nor `apt-ftparchive`. So `Packages` is written directly: for each `.deb`, the control fields from `dpkg-deb -f`, then `Filename`, `Size`, `MD5sum` and `SHA256`, then a blank line. `Release` is a header (`Origin`, `Suite`, `Codename`, `Architectures`, `Components`, `Date`) and a `SHA256:` list of the three `Packages*` files. Using one implementation means a local build and the CI build are the same code.

## Signing

When `SIGN_KEY` is set the script produces `InRelease` (`gpg --clearsign`) and `Release.gpg` (`gpg -abs`) and exports the public key twice. apt prefers `InRelease`. Without `SIGN_KEY` it warns that the repository is **unsigned**, for local experiments only; [`update.yaml`](../../../../.github/workflows/update.yaml) refuses to run without the key.

The key is Ed25519 (OpenPGP v4). Ed448 was tried and rejected; see [SECURITY.md](../../../../SECURITY.md#signing-key).

## What the index promises

apt checks `InRelease` against the trusted key, then each index file against the hashes in `Release`, then each `.deb` against the `SHA256` in `Packages`. A `.deb` therefore cannot be swapped without re-signing. The repository holds the *current* stable and preview only (it is rebuilt from scratch each run); older versions are release assets.

## Adding something

A new package is a new call to `build-deb.sh` in the workflow's build step; `build-repo.sh` picks up every `.deb` in the folder. A new architecture or suite would change the layout above and the install instructions; both are deliberate, documented changes.
