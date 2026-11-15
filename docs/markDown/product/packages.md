# Packages

The repository (`deb [signed-by=…] https://pwsh-termux.machlev.org stable main`) serves three packages. `$PREFIX` is `/data/data/com.termux/files/usr`.

1. **`pwsh`** (`aarch64`): the highest stable PowerShell release. Installs to `$PREFIX/opt/pwsh`, with the command `$PREFIX/bin/pwsh`.
2. **`pwsh-preview`** (`aarch64`): the highest preview or release candidate, while it is newer than stable. Installs to `$PREFIX/opt/pwsh-preview`, with the command `$PREFIX/bin/pwsh-preview`.
3. **`pwsh-termux-keyring`** (`all`): the repository's public keys, as `$PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg`, and the `signed-by` source line, as `$PREFIX/etc/apt/sources.list.d/pwsh-termux.list`. New keys arrive with `pkg upgrade`. It has its own version, not tied to a PowerShell release ([keyring](../engineering/architecture/keyring.md)).

Every package also installs `$PREFIX/share/doc/<package>/copyright`. `pwsh` and `pwsh-preview` share no files and install side by side.

## Which release becomes which package

1. **stable**: the highest version among published, non-prerelease releases with a `linux-arm64` tarball.
2. **preview**: the highest prerelease, only if its core version (before any `-`) is greater than stable's. After `7.7.0` ships, `7.7.0-rc.1` is no longer published; `7.8.0-preview.1` would be.

Details, including why the choice is by version and not date: [releases](../engineering/architecture/releases.md).

## Version numbers

The package version is Microsoft's, with a Debian revision:

1. `v7.7.0` → `7.7.0-1`.
2. `v7.7.0-rc.1` → `7.7.0~rc.1-1`. `~` sorts before the empty string, so `7.7.0~rc.1-1` < `7.7.0-1`. `pwsh-preview` and `pwsh` are separate packages: `pkg upgrade` never swaps one for the other, so install `pwsh` for the final release. An installed `pwsh-preview` stays as it is until a newer preview qualifies.
3. `v7.8.0-preview.2` → `7.8.0~preview.2-1`.

The revision (`-1` unless [`packaging-revisions`](../../../packaging-revisions) gives another) is for re-releasing the same PowerShell build, after a packaging fix or when a release tag name is burned ([revisions](../engineering/architecture/packaging.md#revisions)). `7.7.0` is `7.7.0-2`.

## Dependencies

`pwsh` and `pwsh-preview` depend on `glibc`, `gcc-libs-glibc`, `libicu-glibc`, `openssl-glibc` and `zlib-glibc`, from [Termux's glibc repository](https://github.com/termux/glibc-packages) (`pkg install glibc-repo`). `pwsh-termux-keyring` depends on nothing. Why ICU: [packaging](../engineering/architecture/packaging.md#why-libicu-glibc).

## What the repository holds

The apt index lists only the current stable and preview; each run rebuilds it from Microsoft's latest releases. Older builds stay as [release assets](https://github.com/EliorMachlev/pwsh-termux/releases), tagged `<package>-<version>` with `~` as `-` (Git tags cannot contain `~`), for example `pwsh-preview-7.8.0-preview.2-1`.

## Pinning or downgrading

apt does not downgrade by itself. Download the older `.deb` from its release and install it:

```bash
dpkg -i pwsh_7.6.10-1_aarch64.deb
apt-mark hold pwsh            # stop pkg upgrade from replacing it
```

Undo with `apt-mark unhold pwsh`.

## Coming from a manual install

If you installed PowerShell by hand (a tarball in `~/.local/share/powershell` and a wrapper in `$PREFIX/bin/pwsh`), `pkg install pwsh` replaces the wrapper with the package's symlink. The manual install still works at its own path but is no longer used; remove it when you are happy with the package.

## Not provided

- 32-bit Arm and x86 packages.
- apt suites other than `stable`.
- Older release lines (for example a `7.4.x` LTS) while a newer stable exists.
- Microsoft's `.msix`, `.pkg` and `.rpm` builds.
