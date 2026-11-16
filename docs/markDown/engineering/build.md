# Build

Everything here runs in Termux on a phone and on Linux, with the same scripts. The commands are written for Termux; on Linux, drop `PATCHELF=…` (the default is `patchelf` on `PATH`) and first `export PREFIX=/data/data/com.termux/files/usr`, the path the packages install under.

## Toolchain

1. `bash`, `curl`, `jq`, `python3`, `tar`, `sha256sum`, `dpkg-deb`: preinstalled on Termux (or `pkg install`) and on the CI runner (Ubuntu 24.04).
2. `patchelf`: Termux `pkg install patchelf-glibc` (binary at `$PREFIX/glibc/bin/patchelf`); Ubuntu `apt-get install patchelf`.
3. `gpg`: Termux `pkg install gnupg`; preinstalled on the runner.
4. `xz`: Termux `pkg install xz-utils`; Ubuntu `apt-get install xz-utils`.

## Termux quirks

1. **No `/usr/bin/env`**: run `bash scripts/<name>.sh`, not `./scripts/<name>.sh`.
2. **`umask` is 077.** `build-deb.sh` and `build-keyring.sh` set `umask 022`; do the same in any script that creates packaged files.
3. **No `dpkg-scanpackages` or `apt-ftparchive`.** `build-repo.sh` does not need them.
4. **Use the glibc `patchelf`**: `PATCHELF=$PREFIX/glibc/bin/patchelf`.

## Build a package

```bash
PATCHELF=$PREFIX/glibc/bin/patchelf DEB_COMPRESSION=gzip \
  bash scripts/build-deb.sh pwsh v7.7.0 out
```

This gives `out/pwsh_7.7.0-2_aarch64.deb` (the revision is from [`packaging-revisions`](architecture/packaging.md#revisions)); `gzip` is much quicker than the default `xz` on a phone. `pwsh-preview v7.7.0-rc.1` shows the `~` version. Inspect with `dpkg-deb -I` (control) and `dpkg-deb -c` (contents: `pwsh` and `createdump`, the `bin/pwsh` symlink, `copyright`).

Offline tests, with fake tarballs and stub downloads (seconds each):

```bash
PATCHELF=$PREFIX/glibc/bin/patchelf bash scripts/test-build-deb.sh
bash scripts/test-find-releases.sh
bash scripts/test-make-sboms.sh
bash scripts/test-assemble-site.sh
```

`bash scripts/find-releases.sh` prints what the pipeline would build now (set `GITHUB_TOKEN` to avoid the anonymous rate limit).

## Testing on a device

CI's x86 runner cannot run the arm64 binary, so this is what proves the patched loader works; run it whenever you change `build-deb.sh`. Extract to a scratch folder, without installing:

```bash
T=$(mktemp -d)
dpkg-deb -x out/pwsh_7.7.0-2_aarch64.deb "$T"
"$T$PREFIX/opt/pwsh/pwsh" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
"$T$PREFIX/bin/pwsh"      -NoProfile -Command '1 + 1'      # through the symlink
rm -rf "$T"
```

## Build the keyring package

```bash
bash scripts/check-keys.sh                 # the key rules; prints the fingerprint
bash scripts/test-keys.sh                  # rules, publish and recovery checks, throwaway keys
bash scripts/test-release-tags.sh          # signed release tags, throwaway keys, local remote
bash scripts/build-keyring.sh out          # out/pwsh-termux-keyring_<version>_all.deb
bash scripts/build-keyring.sh out2 && cmp out/pwsh-termux-keyring_*_all.deb out2/pwsh-termux-keyring_*_all.deb
```

The two builds must be byte-identical ([keyring](architecture/keyring.md#deterministic)).

## Build and test a repository

```bash
bash scripts/build-repo.sh out repo                  # unsigned: fine locally
bash scripts/assemble-site.sh docs repo              # needs a full Git clone, not --depth 1
```

To test signing and let real `apt` read the result without touching your sources, use a throwaway Ed25519 key and an isolated apt configuration. `build-repo.sh` signs only with the key in `keys/`, so point the test-only `KEYRING_FILE` at a keyring holding the throwaway key, in a folder of its own (a `ROTATION` file next to it would count), and build the keyring package from it. `KEYRING_DEB_SHA256` stands in for the digest from the workflow's `verify` job ([publish checks](architecture/signing.md#publish-checks)).

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
# a passphrase-protected key, as in CI: GPG_PASSPHRASE_FILE=<mode-600 file> bash scripts/build-repo.sh out repo

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

With `sourceparts` pointed at `$X$PREFIX/etc/apt/sources.list.d` instead, apt reads the package's own source line; without the package installed it reports the key file missing, which shows the line parses. Ed25519 matters: an Ed448 key looks fine to `gpg`, but apt 2.8 reports a bad signature ([SECURITY.md](../../../SECURITY.md#signing-key)).

## Test the schedule keep-alive

```bash
bash scripts/test-keepalive.sh                                   # offline, stub gh
GH_REPO=EliorMachlev/pwsh-termux bash scripts/keep-schedules-alive.sh check              # real states, read only
GH_REPO=EliorMachlev/pwsh-termux bash scripts/keep-schedules-alive.sh refresh --dry-run  # what refresh would enable
```

Both real calls use your `gh` login and write nothing ([keep-alive](ci-cd/keepalive.md#schedule-keep-alive)).

## Check the sign-offs

```bash
bash scripts/test-dco.sh                                  # offline, in a throwaway repository
bash scripts/check-dco.sh your-login HEAD origin/main     # your branch, as the DCO check sees it
```

Every commit your branch adds needs a `Signed-off-by:` trailer naming its author ([DCO](contributing.md#developer-certificate-of-origin)).

## Check the website

```bash
python3 .github/scripts/site-check.py docs
```

The [HTML and CSS validation](website-checks.md#valid-html-and-css) needs Java 17+ and Node.js (`pkg install openjdk-25 nodejs`). In Termux, call npm through node, as its launcher needs `/usr/bin/env`:

```bash
(cd tools/site-lint && node "$PREFIX/lib/node_modules/npm/bin/npm-cli.js" ci --ignore-scripts)
VNU_JAR=tools/site-lint/node_modules/vnu-jar/build/dist/vnu.jar
bash scripts/test-validate-site.sh "$VNU_JAR"
bash scripts/validate-site.sh "$VNU_JAR" docs
bash scripts/validate-site.sh "$VNU_JAR" art/brand
node tools/site-lint/node_modules/stylelint/bin/stylelint.mjs --config tools/site-lint/.stylelintrc.json \
  --ignore-disables --max-warnings 0 docs/*.css
```

## Regenerate the diagrams

The animated diagrams of the README and `INSTALL.md` ([website.md](website.md#diagrams); the site uses HTML lists) are drawn by `tools/diagrams/gen.mjs`. Needs `node`, `ffmpeg`, `rsvg-convert` (librsvg) and the Roboto font.

1. Edit the steps at the top of `gen.mjs`.
2. `node tools/diagrams/gen.mjs "$PWD/out"` (absolute folder).
3. Copy the 640-wide `<name>.gif` files to `docs/img/`; the `@2x` and `-still` files are not used.
4. Copy each `.mmd` into the Mermaid `<details>` blocks of `README.md`, `INSTALL.md`, `docs/index.html` and `docs/install.html`; update the `<ol>` steps in the two pages and the `alt` text of the GIFs if the steps changed.

On Termux: `pkg install librsvg fontconfig ffmpeg`, and pass `FONTCONFIG_FILE` pointing to a file with `<fontconfig><include ignore_missing="yes">$PREFIX/etc/fonts/fonts.conf</include><dir>/system/fonts</dir></fontconfig>`.

## Lint

```bash
shellcheck --shell=bash --severity=style scripts/*.sh scripts/lib/*.sh        # pkg install shellcheck
python3 -I -m py_compile .github/scripts/site-check.py
```

Docs checks (lychee, typos), workflow audits (jactionlint, zizmor) and fuzzing of `spdx-build-view.py` run in CI ([ci-cd.md](ci-cd.md)).
