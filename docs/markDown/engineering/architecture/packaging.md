# Packaging

[`scripts/build-deb.sh`](../../../../scripts/build-deb.sh) turns one Microsoft release into one `.deb`:

```bash
bash scripts/build-deb.sh <pwsh|pwsh-preview> <tag> <outdir>
```

It prints the path of the `.deb` on stdout; all messages go to stderr.

## Steps

1. **Validate** the package name and the tag (`^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`), so nothing odd reaches a URL.
2. **Download** `powershell-<version>-linux-arm64.tar.gz` and `hashes.sha256` from the release.
3. **Verify.** `hashes.sha256` is a **UTF-16 file with a byte-order mark**, so `grep` cannot read it; a short Python snippet decodes it and finds the line for the tarball. The SHA-256 of the download must equal that value or the build stops.
4. **Extract** into the package's `opt` folder.
5. **Patch** every ELF executable that has a loader (here `pwsh` and `createdump`; shared libraries have none): `patchelf --set-interpreter $PREFIX/glibc/lib/ld-linux-aarch64.so.1` and `--set-rpath $PREFIX/glibc/lib:$PREFIX/opt/<package>`. The build fails if nothing was patched or if `pwsh`'s interpreter is not the expected one afterwards.
6. **Lay out** the package: `bin/<package>` symlink to `../opt/<package>/pwsh`, and `share/doc/<package>/copyright` (a note that this is an unofficial repackaging, then Microsoft's `LICENSE.txt`).
7. **Describe** it in `DEBIAN/control` (below) and **build** with `dpkg-deb --root-owner-group -Zxz`.

The script sets `umask 022` first: Termux's default `umask` of 077 would make `DEBIAN` mode 0700, which `dpkg-deb` rejects, and would give packaged directories the wrong permissions.

## Control file

```text
Package: pwsh                       (or pwsh-preview)
Version: 7.7.0-1                    (7.7.0~rc.1-1 for a release candidate; see ../../product/packages.md)
Architecture: aarch64
Depends: glibc, gcc-libs-glibc, libicu-glibc, openssl-glibc, zlib-glibc
Section: shells
Homepage: https://github.com/PowerShell/PowerShell
```

The description says the package is an unofficial repackaging, not affiliated with Microsoft. Environment knobs: `PATCHELF` (default `patchelf`), `TERMUX_PREFIX` (default `/data/data/com.termux/files/usr`), `REVISION` (default `1`), `DEB_COMPRESSION` (`xz`, or `gzip` for a quicker local build).

## Why patchelf and not glibc-runner

Termux's own libc is Android's bionic, so Microsoft's glibc binary cannot start without a glibc loader. `glibc-runner` (`grun`) solves that by launching programs as `ld.so <program>`. That fails for PowerShell: `pwsh` is a .NET launcher stub that finds `pwsh.dll` next to **the executable it was started from**, and under `grun` that executable is the loader, so it looks in `$PREFIX/glibc/lib/` and stops with *"The application to execute does not exist: '.../glibc/lib/pwsh.dll'"*.

Patching the interpreter into the binary makes the kernel start `pwsh` itself, so the stub finds its own folder. The result also needs no wrapper script and works through the `bin/pwsh` symlink (the kernel reports the real path). `glibc-runner` stays useful for programs without such a stub, and as a fallback, but is not used here.

## Why libicu-glibc

.NET aborts at startup with *"Couldn't find a valid ICU package"* unless ICU is present (or invariant globalization is switched on, which would silently change how PowerShell treats culture). The package depends on `libicu-glibc` instead.

## Checks

The `package` job in [`ci.yaml`](../../../../.github/workflows/ci.yaml) builds the real stable package on every change and asserts the interpreter and the symlink. It cannot *run* the arm64 binary on its x86 runner; that check is done on a device ([build](../build.md#testing-on-a-device)).
