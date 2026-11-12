# Build

Everything here runs on a phone in Termux and on Linux. The scripts are the same on both.

## Toolchain

| Tool | Termux | CI (Ubuntu 24.04) |
|---|---|---|
| `bash`, `curl`, `jq`, `python3`, `tar`, `sha256sum` | installed by default or `pkg install` | preinstalled (`jq` ships on the runner) |
| `dpkg-deb` | part of `dpkg` (installed) | preinstalled |
| `patchelf` | `pkg install patchelf-glibc`, binary at `$PREFIX/glibc/bin/patchelf` | `apt-get install patchelf` |
| `gpg` | `pkg install gnupg` | preinstalled |
| `xz` | `pkg install xz-utils` | `apt-get install xz-utils` |

## Termux quirks

- **No `/usr/bin/env`**, so `#!/usr/bin/env bash` scripts cannot be executed directly: run `bash scripts/<name>.sh`.
- **`umask` is 077** in a normal Termux shell. `build-deb.sh` sets `umask 022` itself; do the same in any script that creates files that get packaged.
- **`dpkg-scanpackages` and `apt-ftparchive` do not exist.** `build-repo.sh` does not need them.
- **Use the glibc `patchelf`**: `PATCHELF=$PREFIX/glibc/bin/patchelf`.

## Build a package

```bash
PATCHELF=$PREFIX/glibc/bin/patchelf DEB_COMPRESSION=gzip \
  bash scripts/build-deb.sh pwsh v7.7.0 out
```

`DEB_COMPRESSION=gzip` is much quicker than the default `xz` on a phone. The result is `out/pwsh_7.7.0-1_aarch64.deb`. Try a prerelease the same way with `pwsh-preview v7.7.0-rc.1` to see the `~` version.

Check it: `dpkg-deb -I out/*.deb` (control), `dpkg-deb -c out/*.deb` (contents: `pwsh` and `createdump` executable, the `bin/pwsh` symlink, the `copyright` file).

## Testing on a device

Extract to a scratch folder and run the binary there, without installing it:

```bash
T=$(mktemp -d)
dpkg-deb -x out/pwsh_7.7.0-1_aarch64.deb "$T"
"$T$PREFIX/opt/pwsh/pwsh" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
"$T$PREFIX/bin/pwsh"      -NoProfile -Command '1 + 1'      # through the symlink
rm -rf "$T"
```

The CI runner is x86 and cannot execute the arm64 binary, so this step is the one that proves the patched loader works; run it when you change `build-deb.sh`.

## Build the keyring package

```bash
bash scripts/check-keys.sh                 # the key rules; prints the fingerprint
bash scripts/test-keys.sh                  # the rules, the publish and recovery checks, with throwaway keys
bash scripts/build-keyring.sh out          # out/pwsh-termux-keyring_<version>_all.deb
bash scripts/build-keyring.sh out2 && cmp out/pwsh-termux-keyring_*_all.deb out2/pwsh-termux-keyring_*_all.deb
```

The build is deterministic: run it twice and the bytes are the same ([details](architecture/repository.md#the-keyring-package)). It sets `umask 022` itself.

## Build and test a repository

```bash
bash scripts/build-repo.sh out repo                  # unsigned: fine locally
bash scripts/assemble-site.sh docs repo              # merge the website
```

To test signing and let real `apt` read the result, without touching your system's sources, use a throwaway key and an isolated apt configuration. `build-repo.sh` refuses to sign with a key that is not the key in `keys/`, so point the test-only `KEYRING_FILE` at a keyring holding the throwaway key, in a folder of its own (a `ROTATION` file next to it would count), and build the keyring package from it. `KEYRING_DEB_SHA256` stands in for the digest the workflow's `verify` job takes from the attestation (the publish step never sets `KEYRING_FILE`):

```bash
export GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key "test <test@example.invalid>" ed25519 sign never
SIGN_KEY=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
export SIGN_KEY
export KEYRING_FILE=$(mktemp -d)/pwsh-termux-archive-keyring.gpg   # TEST ONLY
gpg --export "$SIGN_KEY" > "$KEYRING_FILE"
rm -f out/pwsh-termux-keyring_*                      # the one built from keys/, if any
bash scripts/build-keyring.sh out
export KEYRING_DEB_SHA256=$(sha256sum < out/pwsh-termux-keyring_*_all.deb | cut -d' ' -f1)
bash scripts/build-repo.sh out repo

# apt reads the key from the keyring package's own layout, as on a device
X=$(mktemp -d); dpkg-deb -x repo/pwsh-termux-keyring.deb "$X"
S=$(mktemp -d); mkdir -p "$S/lists/partial" "$S/cache/archives/partial"
echo "deb [signed-by=$X$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg] file://$PWD/repo stable main" > "$S/sources.list"
O="-o Dir::Etc::sourcelist=$S/sources.list -o Dir::Etc::sourceparts=/dev/null \
   -o Dir::State::lists=$S/lists -o Dir::Cache=$S/cache -o Debug::NoLocking=1 -o APT::Sandbox::User="
apt-get $O update
apt-cache $O policy pwsh
apt-get $O -s install pwsh pwsh-termux-keyring   # -s: simulate only
```

The same `$O` with `sourceparts` pointed at `$X$PREFIX/etc/apt/sources.list.d` reads the package's own source line verbatim; on a device without the package installed, apt then reports the key file as missing, which shows the line itself parses.

Use Ed25519 for the test key: an Ed448 key looks fine to `gpg` but apt 2.8 reports a bad signature ([SECURITY.md](../../../SECURITY.md#signing-key)).

## Check the website

```bash
python3 .github/scripts/site-check.py docs
```

## Lint

```bash
shellcheck --shell=bash --severity=style scripts/*.sh        # pkg install shellcheck
python3 -I -m py_compile .github/scripts/site-check.py
```

The docs checks (lychee for links, typos for spelling) and the workflow audits (actionlint, zizmor) run in CI; [ci-cd.md](ci-cd.md) lists them.

## Find releases

`bash scripts/find-releases.sh` prints what the pipeline would build right now (set `GITHUB_TOKEN` to avoid the API's anonymous rate limit).
