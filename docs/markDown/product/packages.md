# Packages

Three packages come from the repository (`deb [signed-by=…] https://pwsh-termux.machlev.org stable main`): `pwsh` and `pwsh-preview` for `aarch64`, and `pwsh-termux-keyring` for `all`.

| Package | Command | Installs to | Follows |
|---|---|---|---|
| `pwsh` | `pwsh` | `$PREFIX/opt/pwsh` | The highest stable PowerShell release |
| `pwsh-preview` | `pwsh-preview` | `$PREFIX/opt/pwsh-preview` | The highest preview or release candidate, while it is newer than stable |
| `pwsh-termux-keyring` | none | `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`, `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list` | The public signing key in [`keys/`](../../../keys) (two keys only during a planned rotation, which then arrives with `pkg upgrade`) and the `signed-by` source line; its own version (`KEYRING_VERSION`), not tied to a PowerShell release ([details](../engineering/architecture/repository.md#the-keyring-package)) |

`$PREFIX` is `/data/data/com.termux/files/usr`. `pwsh` and `pwsh-preview` also install a symlink `$PREFIX/bin/<command>` pointing into their `opt` folder; every package installs `$PREFIX/share/doc/<package>/copyright`. `pwsh` and `pwsh-preview` share no files and install side by side.

## Which release becomes which package

[`scripts/find-releases.sh`](../../../scripts/find-releases.sh) lists Microsoft's releases and picks:

- **stable**: the highest version among releases that are not drafts or prereleases and have a `linux-arm64` tarball;
- **preview**: the highest prerelease, but only if its core version (the part before any `-`) is **greater** than stable's. Right after Microsoft ships `7.7.0`, an old `7.7.0-rc.1` is no longer published as a preview; `7.8.0-preview.1` would be.

It chooses by version, not by date, because Microsoft backports patches to older lines (a `7.4.x` release can appear after `7.7.0`). A release whose tarball is not uploaded yet is skipped until the next run.

## Version numbers

The package version is Microsoft's, with a Debian revision:

| Microsoft tag | Package version | Notes |
|---|---|---|
| `v7.7.0` | `7.7.0-1` | |
| `v7.7.0-rc.1` | `7.7.0~rc.1-1` | `~` sorts before the empty string, so `7.7.0~rc.1-1` < `7.7.0-1`: a preview user moves to the final release on `pkg upgrade` |
| `v7.8.0-preview.2` | `7.8.0~preview.2-1` | |

The revision (`-1`) is for packaging fixes that do not change PowerShell; it is `REVISION` in `build-deb.sh`.

## Dependencies

`pwsh` and `pwsh-preview` depend on `glibc`, `gcc-libs-glibc`, `libicu-glibc`, `openssl-glibc` and `zlib-glibc`, all from [Termux's glibc repository](https://github.com/termux/glibc-packages) (`pkg install glibc-repo`); `pwsh-termux-keyring` depends on nothing. `libicu-glibc` is needed because .NET refuses to start without ICU unless globalization is switched to invariant mode, which the package does not do.

## What the repository holds

The apt index lists the **current** stable and preview only; the build is stateless, so each run rebuilds from Microsoft's latest releases. Older builds are kept as [release assets](https://github.com/EliorMachlev/pwsh-termux/releases), tagged `<package>-<version>` (a `~` becomes `-`, since a Git tag cannot contain it: `pwsh-preview-7.8.0-preview.2-1`).

## Pinning or downgrading

apt will not downgrade by itself. To go back to an older build, download its `.deb` from the release and install it:

```bash
dpkg -i pwsh_7.6.10-1_aarch64.deb
apt-mark hold pwsh            # stop pkg upgrade from replacing it
```

Undo the hold with `apt-mark unhold pwsh`.

## Coming from a manual install

If you installed PowerShell by hand (a tarball in `~/.local/share/powershell` and a wrapper in `$PREFIX/bin/pwsh`), `pkg install pwsh` replaces the wrapper with the package's symlink. The manual install keeps working at its own path but is no longer used; remove it when you are happy with the package.

## Not provided

32-bit Arm and x86 packages, apt suites other than `stable`, older release lines (for example a `7.4.x` LTS) while a newer stable exists, and Microsoft's `.msix`, `.pkg` and `.rpm` builds.
