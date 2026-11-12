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

## Build and test a repository

```bash
bash scripts/build-repo.sh out repo                  # unsigned: fine locally
bash scripts/assemble-site.sh docs repo              # merge the website
```

To test signing and let real `apt` read the result, without touching your system's sources, use a throwaway key and an isolated apt configuration:

```bash
export GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key "test <test@example.invalid>" ed25519 sign never
SIGN_KEY=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
export SIGN_KEY
bash scripts/build-repo.sh out repo

S=$(mktemp -d); mkdir -p "$S/lists/partial" "$S/cache/archives/partial"
echo "deb [signed-by=$PWD/repo/pwsh-termux.gpg] file://$PWD/repo stable main" > "$S/sources.list"
O="-o Dir::Etc::sourcelist=$S/sources.list -o Dir::Etc::sourceparts=/dev/null \
   -o Dir::State::lists=$S/lists -o Dir::Cache=$S/cache -o Debug::NoLocking=1 -o APT::Sandbox::User="
apt-get $O update
apt-cache $O policy pwsh
apt-get $O -s install pwsh          # -s: simulate only
```

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
