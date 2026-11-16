# The keyring package

Users must trust the key once. [`scripts/build-keyring.sh`](../../../../scripts/build-keyring.sh) packs it so that this is one `dpkg -i`.

## Content

`pwsh-termux-keyring` (`Architecture: all`) installs:

1. `share/keyrings/pwsh-termux-archive-keyring.gpg`: the file from `keys/` ([key rules](signing.md#key-rules));
2. `etc/apt/sources.list.d/pwsh-termux.list`: the `signed-by` source line ([repository](repository.md#layout));
3. `share/doc/pwsh-termux-keyring/copyright`.

It has no maintainer scripts and no conffiles, so an upgrade replaces both files and `pkg remove` deletes them.

## Build and publish

1. It is built once, in [`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml)'s unprivileged `build` job next to `pwsh`, so it gets the same SBOMs and build provenance.
2. The `verify` job checks that file's provenance only (not its contents), and the `sign` job signs an index that lists it unchanged ([publish checks](signing.md#publish-checks)).
3. `build-repo.sh` indexes it like any package and copies it to `/pwsh-termux-keyring.deb`, the fixed URL the install line downloads.
4. `update.yaml` attaches it, with its SBOMs and the public key, to each new PowerShell release.

## Deterministic

The same key file and script give the same bytes, whoever builds them:

1. every timestamp is `SOURCE_DATE_EPOCH`, by default the key's creation time read from the key file (no Git history needed);
2. xz runs single-threaded (`--threads-max=1`);
3. owners are `root:root` and permissions come from `umask 022`;
4. `Installed-Size` is summed from file sizes, not `du`, which depends on the file system.

CI builds it twice and compares the bytes. That tests reproducibility; it is not a security gate, which is the attestation and content checks.

## Version

`KEYRING_VERSION` at the top of the script is the package's own version, not tied to a PowerShell release. Bump it whenever the content changes (a key added or dropped, the source line, the layout), or `pkg upgrade` will not deliver it.
