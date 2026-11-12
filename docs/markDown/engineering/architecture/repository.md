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
├── pool/main/<package>/<package>_<version>_<arch>.deb
├── pwsh-termux.gpg        keys/pwsh-termux-archive-keyring.gpg, unchanged (binary)
├── pwsh-termux.asc        the same keys, armored
└── pwsh-termux-keyring.deb  the keyring package under a fixed name (also in the pool)
```

Clients use `deb [signed-by=/data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg] https://pwsh-termux.machlev.org stable main` in `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list`. The keyring package installs exactly that; the manual install on the site writes the same two files. apt 2.8 (Termux) accepts the absolute `signed-by` path; Termux has no `share/keyrings` folder of its own, so the package and the manual install create it. Keep the file name: two sources for the same URI with different `Signed-By` values are an apt error.

## The index without apt tooling

Termux has neither `dpkg-scanpackages` nor `apt-ftparchive`. So `Packages` is written directly: for each `.deb`, the control fields from `dpkg-deb -f`, then `Filename`, `Size`, `MD5sum` and `SHA256`, then a blank line. `Release` is a header (`Origin`, `Suite`, `Codename`, `Architectures`, `Components`, `Date`) and a `SHA256:` list of the three `Packages*` files. Using one implementation means a local build and the CI build are the same code.

## Signing

When `SIGN_KEY` is set the script produces `InRelease` (`gpg --clearsign`) and `Release.gpg` (`gpg -abs`). apt prefers `InRelease`. Without `SIGN_KEY` it warns that the repository is **unsigned**, for local experiments only; [`update.yaml`](../../../../.github/workflows/update.yaml) refuses to run without the key.

The public key comes from Git, not from the signing key: [`keys/pwsh-termux-archive-keyring.gpg`](../../../../keys/pwsh-termux-archive-keyring.gpg) is published as `pwsh-termux.gpg` byte for byte, and armored as `pwsh-termux.asc` (checked to dearmor to the same bytes).

**Key rules** ([`scripts/check-keys.sh`](../../../../scripts/check-keys.sh); CI's `keys` job and every signing run apply them, all fail closed). The file is binary OpenPGP with no secret material, and keys/ holds nothing else except, during a rotation, `keys/ROTATION`:

- **Steady state** (no `keys/ROTATION`): exactly one primary key, and it is the signing key.
- **Rotation** (`keys/ROTATION` committed, one line: the fingerprint of the next key): exactly two primary keys, one of them the key the marker names, and the signing key is one of the two. A marker next to a single key is stale and refused, so the last rotation step cannot leave it behind.

**Publish checks.** `update.yaml` has a `verify` job, with a read-only token and no signing key, that runs [`scripts/verify-attestation.sh`](../../../../scripts/verify-attestation.sh) on the keyring package the build job uploaded: `gh attestation verify --repo EliorMachlev/pwsh-termux --signer-workflow …/build-packages.yaml --source-digest <this commit> --deny-self-hosted-runners`. It outputs the file's SHA-256. The `publish` job then runs `build-repo.sh` with the signing key and `KEYRING_DEB_SHA256` set to that digest, and the script refuses to sign unless:

- `keys/` passes the key rules above, and the signing key's fingerprint is the key in it (or one of the two during a marked rotation);
- the folder of `.deb` files holds exactly one `pwsh-termux-keyring`, its SHA-256 is `KEYRING_DEB_SHA256` (the file whose provenance was verified), and it ships `keys/pwsh-termux-archive-keyring.gpg` byte for byte;
- `InRelease` and `Release.gpg` verify with `gpgv` against `keys/` alone, as apt will.

It publishes that verified file as it is. A secret replaced without changing `keys/`, or the reverse, publishes nothing.

What these prove: the package users install was built by this repository's `build-packages.yaml` from the commit being published, and it contains exactly the committed `keys/`, whose key is the one that signs the index. They do not prove that `keys/` holds the *right* key: that rests on review of changes to `keys/` and on users comparing the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key).

`KEYRING_FILE` overrides the key file (and the `ROTATION` next to it) for tests with throwaway keys only ([build](../build.md#build-and-test-a-repository)); the signing step in `update.yaml` clears it. [`scripts/test-keys.sh`](../../../../scripts/test-keys.sh) tests every rule and refusal with throwaway keys and a stub `gh`.

The key is Ed25519 (OpenPGP v4). Ed448 was tried and rejected; see [SECURITY.md](../../../../SECURITY.md#signing-key).

## The keyring package

A user must trust the key once. [`scripts/build-keyring.sh`](../../../../scripts/build-keyring.sh) packs it so that this is one `dpkg -i`: `pwsh-termux-keyring` (`Architecture: all`) installs `share/keyrings/pwsh-termux-archive-keyring.gpg` (the file from `keys/`) and `etc/apt/sources.list.d/pwsh-termux.list` (the `signed-by` line above), plus its `copyright`. It has no maintainer scripts. Neither file is a conffile, so an upgrade replaces both and `pkg remove` deletes both.

It is built once, in [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml)'s unprivileged `build` job next to `pwsh`, so it gets the same SBOMs and build provenance; the publish job checks that file (above) and publishes it. `build-repo.sh` lists it in the index like any other package and copies it to `/pwsh-termux-keyring.deb`, the fixed URL the install line downloads from. `update.yaml` also attaches it, with its SBOMs, to each new PowerShell release, next to the public key.

**Deterministic.** The same key file and script give the same bytes, whoever builds them: every file's timestamp is `SOURCE_DATE_EPOCH`, which defaults to the key's creation time read from the key file (no Git history needed), xz runs single-threaded (`--threads-max=1`), owners are `root:root`, permissions come from `umask 022`, and `Installed-Size` is summed from file sizes rather than `du`, which depends on the file system. CI builds it twice and compares the bytes. That is a reproducibility test, not a security gate: the publish job relies on the attestation and the content checks above, not on a second build.

**Version.** `KEYRING_VERSION` at the top of the script; bump it whenever the content changes (a key added or dropped, the source line, the layout), or `pkg upgrade` will not deliver it.

**Rotation.** apt accepts an index signed by any key in the `signed-by` file, and the keyring package is in the signed index. So a planned rotation first ships a keyring with the old and the next key (marked by `keys/ROTATION`) while the old key still signs, and `pkg upgrade` delivers it; the signing switches to the next key only after a grace period ([release](../release.md#rotating-the-signing-key)). A compromised key cannot hand over to its successor this way, since whoever holds it could sign a keyring of their own: users then reinstall the keyring by hand, after an advisory.

The first install still rests on HTTPS, which is why the docs tell users to compare the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key) and offer `gh attestation verify` on the downloaded package.

## What the index promises

apt checks `InRelease` against the trusted key, then each index file against the hashes in `Release`, then each `.deb` against the `SHA256` in `Packages`. A `.deb` therefore cannot be swapped without re-signing. The repository holds the *current* stable and preview only (it is rebuilt from scratch each run); older versions are release assets.

## Adding something

A new package is a new call to `build-deb.sh` in the workflow's build step; `build-repo.sh` picks up every `.deb` in the folder. A new architecture or suite would change the layout above and the install instructions; both are deliberate, documented changes.
