# The apt repository

[`scripts/build-repo.sh`](../../../../scripts/build-repo.sh) builds an unsigned repository from a folder of `.deb` files; [`sign-release.sh`](../../../../scripts/sign-release.sh) signs its `Release` ([signing](signing.md)):

```bash
bash scripts/build-repo.sh debs repo
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

Clients use this line in `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list`:

```text
deb [signed-by=/data/data/com.termux/files/usr/share/keyrings/pwsh-termux-archive-keyring.gpg] https://pwsh-termux.machlev.org stable main
```

The [keyring package](keyring.md) and the site's manual install write exactly that and the key (creating `share/keyrings`, which Termux lacks). Keep the file name: two sources for one URI with different `Signed-By` values are an apt error.

## The index without apt tooling

Termux has neither `dpkg-scanpackages` nor `apt-ftparchive`, so the index is written directly, by the same code locally and on CI:

1. `Packages`: for each `.deb`, its control fields (`dpkg-deb -f`), then `Filename`, `Size`, `MD5sum`, `SHA256` and a blank line; then `gzip -n` and `xz` copies.
2. `Release`: `Origin`, `Suite`, `Codename`, `Architectures`, `Components`, `Date`, `Valid-Until`, `Description`, and a `SHA256:` list of the three `Packages*` files.

## Signing

`build-repo.sh` writes no signature. `sign-release.sh sign` (in [`update.yaml`](../../../../.github/workflows/update.yaml)'s `sign` job) writes `InRelease` (`gpg --clearsign`, preferred by apt) and `Release.gpg` (`gpg -abs`), and `install` adds them to the repository the `publish` job rebuilds. The public key comes from Git, not the secret: `keys/pwsh-termux-archive-keyring.gpg` is published byte for byte as `pwsh-termux.gpg` and armored as `pwsh-termux.asc`. Key rules, pre-signing checks, rotation and recovery: [signing](signing.md).

## The keyring package

`build-repo.sh` indexes `pwsh-termux-keyring` and copies it to `/pwsh-termux-keyring.deb`, the fixed URL the install line downloads ([keyring](keyring.md)).

## Valid-Until

`Valid-Until` is `Date` plus `VALID_UNTIL_DAYS` (14) days, both RFC 1123 in UTC, from one clock reading; `build-repo.sh` checks its own output with `check_release_window` ([`lib/common.sh`](../../../../scripts/lib/common.sh)). apt refuses the index after that date, which limits a freeze or replay attack to 14 days. [`update.yaml`](../../../../.github/workflows/update.yaml) runs daily and re-signs even when nothing changed ([release](../release.md#what-happens-on-a-run)).

Only `Release`, `InRelease` and `Release.gpg` depend on the time. `Packages` comes from the `.deb` files alone, and neither `gzip -n` nor xz stores a name or time, so with reproducible `.deb` builds a daily re-sign changes only the signed release files. [`test-keys.sh`](../../../../scripts/test-keys.sh) builds twice at different times and compares.

An index signed with the recovery key is held to more: [`recovery-sign.sh`](../../../../scripts/recovery-sign.sh) and [`verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) also require a `Date` not in the future, a `Valid-Until` at most 14 days after it, and at least `VALID_UNTIL_WARN_DAYS` (7) days left.

## What the index guarantees

apt checks `InRelease` against the trusted key and its `Valid-Until`, each index file against the hashes in `Release`, and each `.deb` against its `SHA256` in `Packages`, so a `.deb` cannot be swapped without re-signing. The index holds only the current stable and preview (it is rebuilt each run); older versions are [release assets](hosting.md#release-assets).

## Adding a package

Add a `build-deb.sh` call to the build step in [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml); `build-repo.sh` indexes every `.deb` in the folder. A new architecture or suite changes the layout above and the install instructions.
