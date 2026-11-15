# NOTICE

**pwsh-termux** repackages **PowerShell** by Microsoft for Termux. It is not a fork of PowerShell's source: it downloads Microsoft's official release binaries and changes only how they are started.

- Upstream project: <https://github.com/PowerShell/PowerShell>
- Upstream copyright: © Microsoft Corporation
- Upstream license: MIT. The full text ships in every package as `/data/data/com.termux/files/usr/share/doc/<package>/copyright`, and as `LICENSE.txt` in the package's `opt` folder.
- Trademark: "PowerShell" is a trademark of Microsoft. pwsh-termux is an independent community project, not affiliated with or endorsed by Microsoft.

## Modifications by the packaging

The `.deb` packages contain Microsoft's `powershell-<version>-linux-arm64.tar.gz`, after its SHA-256 has matched Microsoft's `hashes.sha256`, with these changes only:

- **Loader.** The two ELF executables with an interpreter (`pwsh` and `createdump`) get Termux's glibc loader (`$PREFIX/glibc/lib/ld-linux-aarch64.so.1`) and an rpath of `$PREFIX/glibc/lib:$PREFIX/opt/<package>`, set with `patchelf`.
- **Layout.** Files install under `$PREFIX/opt/pwsh` (or `$PREFIX/opt/pwsh-preview`), with a `$PREFIX/bin/pwsh` (or `pwsh-preview`) symlink and a `copyright` file under `$PREFIX/share/doc/`.
- **Versions.** A tag such as `v7.7.0-rc.1` becomes the Debian version `7.7.0~rc.1-1`, so a release candidate sorts before its final release.
- **Dependencies.** `glibc`, `gcc-libs-glibc`, `libicu-glibc`, `openssl-glibc` and `zlib-glibc` from [Termux's glibc repository](https://github.com/termux/glibc-packages).

PowerShell's behaviour, including its telemetry and update notice, is Microsoft's and is not changed.

## License

The scripts, workflows, website and documentation in this repository are original work, © pwsh-termux contributors, under the [MIT license](LICENSE), maintained by Elior Machlev. PowerShell is MIT too. Redistributing a package means complying with both: keep the upstream copyright and license text, which every package already carries.
