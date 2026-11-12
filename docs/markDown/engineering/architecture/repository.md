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

The public keys come from Git, not from the signing key: [`keys/pwsh-termux-archive-keyring.gpg`](../../../../keys/pwsh-termux-archive-keyring.gpg) is published as `pwsh-termux.gpg` byte for byte, and armored as `pwsh-termux.asc` (checked to dearmor to the same bytes). When signing, `build-repo.sh` fails closed unless:

- the file holds public keys only ([`scripts/check-keys.sh`](../../../../scripts/check-keys.sh), which CI also runs on `keys/`);
- the signing key's fingerprint is one of its primary keys;
- the folder of `.deb` files holds exactly one `pwsh-termux-keyring` (in the workflow: the one the unprivileged build job built and attested) and it ships exactly that file;
- `build-keyring.sh`, run again in the signing job from the same `keys/` file and the same `SOURCE_DATE_EPOCH`, produces that package **byte for byte**;
- the public key exported from the signing key itself (`gpg --export`, public only) is among the keys in the file that package installs;
- `InRelease` and `Release.gpg` verify with `gpgv` against that file alone, as apt will.

The package that is published is the attested one from the build job, never the rebuild, so `gh attestation verify` works on the shipped file. The rebuild is compared with a package built from `keys/`, not with one built from the exported signing key alone: during a planned rotation `keys/` also holds the next key, so a package from the signing key alone would differ by design. The two checks together say the same thing without that exception: the attested package is exactly what `keys/` produces, and the key that signs is in it.

`KEYRING_FILE` overrides the file, for tests with a throwaway key only ([build](../build.md#build-and-test-a-repository)); the workflows never set it.

The key is Ed25519 (OpenPGP v4). Ed448 was tried and rejected; see [SECURITY.md](../../../../SECURITY.md#signing-key).

## The keyring package

A user must trust the key once. [`scripts/build-keyring.sh`](../../../../scripts/build-keyring.sh) packs it so that this is one `dpkg -i`: `pwsh-termux-keyring` (`Architecture: all`) installs `share/keyrings/pwsh-termux-archive-keyring.gpg` (the file from `keys/`) and `etc/apt/sources.list.d/pwsh-termux.list` (the `signed-by` line above), plus its `copyright`. It has no maintainer scripts. Neither file is a conffile, so an upgrade replaces both and `pkg remove` deletes both.

It is built in [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml)'s unprivileged `build` job, next to `pwsh`, so it gets the same SBOMs and build provenance, and built again in `update.yaml`'s `publish` job, which holds the signing key, to check it (above). The attestation proves which workflow run and commit built the package from that commit's `keys/`; it does not prove those keys are the right ones, which rests on the fingerprint in SECURITY.md and on the publish job's check that the signing key is among them. `build-repo.sh` lists it in the index like any other package and copies it to `/pwsh-termux-keyring.deb`, the fixed URL the install line downloads from. `update.yaml` also attaches it, with its SBOMs, to each new PowerShell release, next to the public key.

**Reproducible.** The same commit gives the same bytes: every file's timestamp is `SOURCE_DATE_EPOCH`, which defaults to the commit time of the key file (`git log -1 --format=%ct -- keys/...`; the build job checks out the full history for this, since a shallow clone would date it by the newest commit). Outside a checkout, or for an uncommitted test keyring, it falls back to the creation time of the newest key in the file. xz runs single-threaded (`--threads-max=1`), owners are `root:root` and permissions come from `umask 022`, and `Installed-Size` is summed from file sizes rather than `du`, which depends on the file system. CI builds it twice and compares the bytes, and the publish job's rebuild compares it again on every run. Both jobs check out the full history so they date it by the same commit.

**Version.** `KEYRING_VERSION` at the top of the script; bump it whenever the content changes (a key added or dropped, the source line, the layout), or `pkg upgrade` will not deliver it.

**Rotation.** apt accepts an index signed by any key in the `signed-by` file. So a planned rotation adds the next key to `keys/` while the old key still signs; `pkg upgrade` delivers both keys before the switch ([release](../release.md#rotating-the-signing-key)). A compromised key cannot hand over to its successor this way (whoever holds it could sign a keyring too), so users then reinstall by hand.

The first install still rests on HTTPS, which is why the docs tell users to compare the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key) and offer `gh attestation verify` on the downloaded package.

## What the index promises

apt checks `InRelease` against the trusted key, then each index file against the hashes in `Release`, then each `.deb` against the `SHA256` in `Packages`. A `.deb` therefore cannot be swapped without re-signing. The repository holds the *current* stable and preview only (it is rebuilt from scratch each run); older versions are release assets.

## Adding something

A new package is a new call to `build-deb.sh` in the workflow's build step; `build-repo.sh` picks up every `.deb` in the folder. A new architecture or suite would change the layout above and the install instructions; both are deliberate, documented changes.
