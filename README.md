# pwsh-termux

Unofficial apt repository that packages Microsoft's official
[PowerShell](https://github.com/PowerShell/PowerShell) `linux-arm64` releases for
**Termux (glibc)**, so `pkg install pwsh` and `pkg upgrade` just work.

> Not affiliated with or endorsed by Microsoft. "PowerShell" is a Microsoft trademark.

## Install

```sh
pkg install glibc-repo          # glibc package repository (if not already enabled)

curl -fsSL https://eliormachlev.github.io/pwsh-termux/pwsh-termux.gpg \
  -o $PREFIX/etc/apt/trusted.gpg.d/pwsh-termux.gpg
echo "deb https://eliormachlev.github.io/pwsh-termux stable main" \
  > $PREFIX/etc/apt/sources.list.d/pwsh-termux.list

pkg update
pkg install pwsh            # stable
pkg install pwsh-preview    # optional: newest preview/RC, installs as `pwsh-preview`
```

The repository is hosted at https://github.com/EliorMachlev/pwsh-termux.

## How it works

A scheduled GitHub Actions workflow (`.github/workflows/update.yml`):

1. `scripts/find-releases.sh` picks the highest **stable** release and, if a newer
   one exists, the highest **prerelease** (Microsoft's `prerelease` flag). It chooses by
   version, not date, because Microsoft backports patches to older lines.
2. `scripts/build-deb.sh` downloads the `linux-arm64` tarball, **verifies it against
   Microsoft's `hashes.sha256`**, patches every ELF executable to use Termux's glibc
   loader (`patchelf`), and builds a `.deb` (`Depends: glibc, gcc-libs-glibc,
   libicu-glibc, openssl-glibc, zlib-glibc`). Prerelease versions map to Debian `~`
   versions (`7.7.0-rc.1` -> `7.7.0~rc.1`) so they upgrade cleanly to the final release.
3. `scripts/build-repo.sh` writes the apt index and GPG-signs it.
4. The repo is deployed to GitHub Pages; each `.deb` is also archived as a GitHub Release asset.

The apt repo only ever contains the *current* stable and preview versions (the build is
stateless, so no large binaries accumulate in git history). Older versions are available as
release assets.

### Why patchelf and not glibc-runner?

`grun` runs programs as `ld.so <program>`. PowerShell's .NET launcher locates `pwsh.dll`
next to the executable, which under `grun` is the loader, so it fails. Patching the
interpreter makes the kernel start `pwsh` directly.

## One-time setup for maintainers

1. Create a **dedicated, passphrase-less** signing key and keep the private half out of git:
   ```sh
   gpg --batch --passphrase '' --quick-generate-key "pwsh-termux <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <fingerprint>     # paste into the secret below
   ```
2. Repository **Settings -> Secrets and variables -> Actions**: add secret `GPG_PRIVATE_KEY`.
3. Repository **Settings -> Pages**: set *Source* to **GitHub Actions**.
4. Run the **Update packages** workflow once (Actions tab -> Run workflow).

Scheduled workflows are disabled by GitHub after 60 days without repository activity; re-enable
them or push a commit occasionally.

## Local build

```sh
# Termux
PATCHELF=$PREFIX/glibc/bin/patchelf DEB_COMPRESSION=gzip bash scripts/build-deb.sh pwsh v7.7.0 out
bash scripts/build-repo.sh out repo          # unsigned unless SIGN_KEY is set
```

## License

Scripts: MIT. PowerShell itself: MIT, (c) Microsoft Corporation; its license is included in each package.
