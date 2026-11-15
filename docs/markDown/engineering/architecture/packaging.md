# Packaging

[`scripts/build-deb.sh`](../../../../scripts/build-deb.sh) turns one Microsoft release into one `.deb`, printing its path on stdout (messages go to stderr):

```bash
bash scripts/build-deb.sh <pwsh|pwsh-preview> <tag> <outdir>
```

## Steps

1. **Validate** the package name and the tag (`^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`), so nothing odd reaches a URL.
2. **Download** `powershell-<version>-linux-arm64.tar.gz` and `hashes.sha256` from the release.
3. **Verify**: the tarball's SHA-256 must equal its line in `hashes.sha256`, or the build stops. That file is UTF-16 with a byte-order mark, so a short Python snippet decodes it (`grep` cannot).
4. **Extract** into `opt/<package>`.
5. **Patch** every ELF executable that has a loader (`pwsh` and `createdump`): `patchelf --set-interpreter $PREFIX/glibc/lib/ld-linux-aarch64.so.1 --set-rpath $PREFIX/glibc/lib:$PREFIX/opt/<package>`. The build fails if nothing was patched or `pwsh`'s interpreter is wrong afterwards.
6. **Lay out** `bin/<package>` (a symlink to `../opt/<package>/pwsh`) and `share/doc/<package>/copyright` (an unofficial-repackaging note, then Microsoft's `LICENSE.txt`).
7. **Build** with `dpkg-deb --root-owner-group --threads-max=1 -Zxz`, reproducibly: every timestamp is `SOURCE_DATE_EPOCH` (default: the newest file time in the tarball), xz is single-threaded, and `Installed-Size` is summed from file sizes, not `du`. An unchanged release rebuilds byte for byte, so the daily run leaves `Packages` unchanged ([repository](repository.md#valid-until)).
8. **Record** `<deb>.build.json` (upstream URL and SHA-256, patchelf version) for the SBOMs; it is not in the package.

The script sets `umask 022` first: Termux's 077 would make `DEBIAN` mode 0700, which `dpkg-deb` rejects.

## Control file

```text
Package: pwsh                       (or pwsh-preview)
Version: 7.7.0-1                    (7.7.0~rc.1-1 for a release candidate)
Architecture: aarch64
Depends: glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc
Section: shells
Homepage: https://github.com/PowerShell/PowerShell
```

The description says the package is an unofficial repackaging, not affiliated with Microsoft. Version mapping: [packages](../../product/packages.md#version-numbers).

Environment variables:

1. `PATCHELF`: the patchelf binary (default `patchelf`).
2. `TERMUX_PREFIX`: default `/data/data/com.termux/files/usr`.
3. `REVISION`: the Debian revision (default `1`).
4. `DEB_COMPRESSION`: `xz` (default) or `gzip`, quicker for local builds.
5. `SOURCE_DATE_EPOCH`: default, the newest file time in the tarball.

## Why patchelf and not glibc-runner

Termux's libc is Android's bionic, so Microsoft's glibc binary needs a glibc loader. `glibc-runner` (`grun`) starts programs as `ld.so <program>`, which breaks PowerShell: the `pwsh` launcher looks for `pwsh.dll` next to the executable it was started from, which under `grun` is the loader, so it fails with *"The application to execute does not exist: '.../glibc/lib/pwsh.dll'"*.

With the interpreter patched into the binary, the kernel starts `pwsh` itself and the launcher finds its own folder. No wrapper script is needed, and the `bin/pwsh` symlink works (the kernel reports the real path).

## Why libicu-glibc

.NET aborts at startup with *"Couldn't find a valid ICU package"* unless ICU is present or invariant globalization is on, which would change how PowerShell handles culture. The package depends on `libicu-glibc` instead.

## Checks

The `package` job in [`ci.yaml`](../../../../.github/workflows/ci.yaml) builds the real stable package twice on every change, compares the bytes, and checks the interpreter and the symlink. Its x86 runner cannot run the arm64 binary; that is tested on a device ([build](../build.md#testing-on-a-device)).
