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

Termux has neither `dpkg-scanpackages` nor `apt-ftparchive`. So `Packages` is written directly: for each `.deb`, the control fields from `dpkg-deb -f`, then `Filename`, `Size`, `MD5sum` and `SHA256`, then a blank line. `Release` is a header (`Origin`, `Suite`, `Codename`, `Architectures`, `Components`, `Date`, `Valid-Until`, `Description`) and a `SHA256:` list of the three `Packages*` files. Using one implementation means a local build and the CI build are the same code.

## Signing

When `SIGN_KEY` is set the script produces `InRelease` (`gpg --clearsign`) and `Release.gpg` (`gpg -abs`). apt prefers `InRelease`. Without `SIGN_KEY` it warns that the repository is **unsigned**, for local experiments only; [`update.yaml`](../../../../.github/workflows/update.yaml) refuses to run without the key.

The public key comes from Git, not from the signing key: [`keys/pwsh-termux-archive-keyring.gpg`](../../../../keys/pwsh-termux-archive-keyring.gpg) is published as `pwsh-termux.gpg` byte for byte, and armored as `pwsh-termux.asc` (checked to dearmor to the same bytes).

**Key rules** ([`scripts/check-keys.sh`](../../../../scripts/check-keys.sh); CI's `keys` job and every signing run apply them, all fail closed). The file is binary OpenPGP with no secret material, and `keys/` holds nothing else except two optional one-line marker files, each holding a 40-hex fingerprint:

- `keys/RECOVERY` names the **recovery key**: an offline key only the maintainer holds, never in GitHub or CI, used only to recover from a lost or compromised online key (below). When the marker exists, that key must be in the keyring.
- `keys/ROTATION` names the **next online key** during a planned rotation; when it exists, that key must be in the keyring and it is not the recovery key.
- Every other key is the **current online key**, and there must be exactly one.

So the allowed shapes are `{current}`, `{current, recovery}`, `{current, next}` and `{current, next, recovery}`; a stray extra key, a marker naming a missing key, and a `ROTATION` marker whose key is the only online key left (stale) all fail. The signer must be the current key, or the next one while `ROTATION` exists, and **never the recovery key**: `build-repo.sh` refuses to sign with it, and refuses to sign at all if its secret is in the same gpg home.

**Publish checks.** `update.yaml` has a `verify` job, with a read-only token and no signing key, that runs [`scripts/verify-attestation.sh`](../../../../scripts/verify-attestation.sh) on the keyring package the build job uploaded: `gh attestation verify --repo EliorMachlev/pwsh-termux --signer-workflow …/build-packages.yaml --source-digest <this commit> --deny-self-hosted-runners`. It outputs the file's SHA-256. The `publish` job then runs `build-repo.sh` with the signing key and `KEYRING_DEB_SHA256` set to that digest, and the script refuses to sign unless:

- `keys/` passes the key rules above, and the signing key is its current online key (or the next one during a marked rotation), not the recovery key, whose secret must not be in the gpg home either;
- the folder of `.deb` files holds exactly one `pwsh-termux-keyring`, its SHA-256 is `KEYRING_DEB_SHA256` (the file whose provenance was verified), and it ships `keys/pwsh-termux-archive-keyring.gpg` byte for byte;
- `InRelease` and `Release.gpg` verify with `gpgv` against `keys/` alone, as apt will.

It publishes that verified file as it is. A secret replaced without changing `keys/`, or the reverse, publishes nothing.

What these prove: the package users install was built by this repository's `build-packages.yaml` from the commit being published, and it contains exactly the committed `keys/`, whose online key is the one that signs the index. They do not prove that `keys/` holds the *right* key: that rests on review of changes to `keys/` and on users comparing the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key).

`KEYRING_FILE` overrides the key file (and the markers next to it) for tests with throwaway keys only ([build](../build.md#build-and-test-a-repository)); the signing step in `update.yaml` clears it. [`scripts/test-keys.sh`](../../../../scripts/test-keys.sh) tests every rule and refusal with throwaway keys and a stub `gh`.

The key is Ed25519 (OpenPGP v4). Ed448 was tried and rejected; see [SECURITY.md](../../../../SECURITY.md#signing-key).

## The keyring package

A user must trust the key once. [`scripts/build-keyring.sh`](../../../../scripts/build-keyring.sh) packs it so that this is one `dpkg -i`: `pwsh-termux-keyring` (`Architecture: all`) installs `share/keyrings/pwsh-termux-archive-keyring.gpg` (the file from `keys/`) and `etc/apt/sources.list.d/pwsh-termux.list` (the `signed-by` line above), plus its `copyright`. It has no maintainer scripts. Neither file is a conffile, so an upgrade replaces both and `pkg remove` deletes both.

It is built once, in [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml)'s unprivileged `build` job next to `pwsh`, so it gets the same SBOMs and build provenance; the publish job checks that file (above) and publishes it. `build-repo.sh` lists it in the index like any other package and copies it to `/pwsh-termux-keyring.deb`, the fixed URL the install line downloads from. `update.yaml` also attaches it, with its SBOMs, to each new PowerShell release, next to the public key.

**Deterministic.** The same key file and script give the same bytes, whoever builds them: every file's timestamp is `SOURCE_DATE_EPOCH`, which defaults to the key's creation time read from the key file (no Git history needed), xz runs single-threaded (`--threads-max=1`), owners are `root:root`, permissions come from `umask 022`, and `Installed-Size` is summed from file sizes rather than `du`, which depends on the file system. CI builds it twice and compares the bytes. That is a reproducibility test, not a security gate: the publish job relies on the attestation and the content checks above, not on a second build.

**Version.** `KEYRING_VERSION` at the top of the script; bump it whenever the content changes (a key added or dropped, the source line, the layout), or `pkg upgrade` will not deliver it.

**Rotation and recovery.** apt accepts an index that *any* key in the `signed-by` file signs, and the keyring package is itself in the signed index, so new keys can reach users through `pkg upgrade` as long as something they already trust signs the index that carries them:

- **Planned rotation**: the next online key is shipped (marked by `keys/ROTATION`) while the current one still signs, and the signer switches only after an overlap of 180 days ([release](../release.md#rotating-the-signing-key)).
- **Compromised or lost online key**: the maintainer signs a repository carrying a keyring with a new online key using the offline **recovery key**, which every installed keyring already trusts ([`scripts/recovery-sign.sh`](../../../../scripts/recovery-sign.sh)), and deploys it with [`recover.yaml`](../../../../.github/workflows/recover.yaml), which holds no key and deploys only what [`scripts/verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) verifies against the recovery key alone ([release](../release.md#recovery-with-the-offline-key)). This works only once the maintainer has added the recovery key (`keys/RECOVERY`), and only while the hosting and the maintainer's GitHub account are intact.

What remains manual (reinstalling the keyring from the site): a user who does not run `pkg upgrade` during an overlap or recovery window, a user who added the key by hand, and the case where the online key is compromised and the recovery key is lost .

The first install still rests on HTTPS, which is why the docs tell users to compare the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key) and offer `gh attestation verify` on the downloaded package.

## Valid-Until

`Valid-Until` is `Date` plus `VALID_UNTIL_DAYS` (14) days, both RFC 1123 dates in UTC, written from one clock reading; `build-repo.sh` checks its own output with `check_release_window` ([`scripts/lib/common.sh`](../../../../scripts/lib/common.sh)). apt refuses the index after that date, which bounds a freeze or replay attack to 14 days. [`update.yaml`](../../../../.github/workflows/update.yaml) runs daily and re-signs the index even when nothing changed, which moves the date on ([release](../release.md#what-happens-on-a-run)).

Only `Release`, `InRelease` and `Release.gpg` depend on the time. `Packages` is made from the `.deb` files alone, `gzip -n` stores no name or time, and xz stores none, so the same packages give byte-identical `Packages`, `Packages.gz` and `Packages.xz`; with reproducible `.deb` builds a daily re-sign changes only the signed release files. [`scripts/test-keys.sh`](../../../../scripts/test-keys.sh) builds twice at different times and compares.

For an index signed with the recovery key, [`recovery-sign.sh`](../../../../scripts/recovery-sign.sh) and [`verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) (run by `recover.yaml` before it deploys) also require a `Date` that is not in the future, a `Valid-Until` at most 14 days after it, and at least `VALID_UNTIL_WARN_DAYS` (7) days left.

## What the index promises

apt checks `InRelease` against the trusted key and its `Valid-Until`, then each index file against the hashes in `Release`, then each `.deb` against the `SHA256` in `Packages`. A `.deb` therefore cannot be swapped without re-signing. The repository holds the *current* stable and preview only (it is rebuilt from scratch each run); older versions are release assets.

## Adding something

A new package is a new call to `build-deb.sh` in the workflow's build step; `build-repo.sh` picks up every `.deb` in the folder. A new architecture or suite would change the layout above and the install instructions; both are deliberate, documented changes.
