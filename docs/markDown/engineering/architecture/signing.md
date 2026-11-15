# Signing keys and publish checks

Which keys may sign the [apt index](repository.md#signing), what is checked before publishing, and how keys change. Procedures: [release](../release.md#rotating-the-signing-key).

## Key rules

[`check-keys.sh`](../../../../scripts/check-keys.sh) applies these in CI's `keys` job and every signing run, failing closed. [`keys/pwsh-termux-archive-keyring.gpg`](../../../../keys/pwsh-termux-archive-keyring.gpg) is binary OpenPGP with no secret material; `keys/` holds nothing else but two optional markers, each one 40-hex fingerprint:

1. `keys/RECOVERY` names the **recovery key**: offline, held only by the maintainer, never in GitHub or CI, used only after losing the online key. It must be in the keyring.
2. `keys/ROTATION` names the **next online key** during a planned rotation. It must be in the keyring and is not the recovery key.
3. Every other key is the **current online key**: exactly one.

Allowed shapes: `{current}`, `{current, recovery}`, `{current, next}`, `{current, next, recovery}`. A stray key, a marker naming a missing key, or a `ROTATION` marker whose key is the only online key left (stale) fails.

The signer must be the current key, or the next one while `ROTATION` exists. `build-repo.sh` refuses the recovery key, and refuses to sign at all if its secret is in the same gpg home. The key is Ed25519 (OpenPGP v4); fingerprint in [SECURITY.md](../../../../SECURITY.md#signing-key).

## Publish checks

[`update.yaml`](../../../../.github/workflows/update.yaml) runs them in two jobs:

1. **`verify`** (read-only token, no signing key) runs [`verify-attestation.sh`](../../../../scripts/verify-attestation.sh) on the keyring package the build uploaded: `gh attestation verify --repo EliorMachlev/pwsh-termux --signer-workflow …/build-packages.yaml --source-digest <this commit> --deny-self-hosted-runners`. It outputs the file's SHA-256.
2. **`publish`** runs `build-repo.sh` with the signing key and `KEYRING_DEB_SHA256` set to that digest.

`build-repo.sh` refuses to sign unless:

1. `keys/` passes the key rules and the signing key is an allowed signer;
2. the `.deb` folder holds exactly one `pwsh-termux-keyring`, with SHA-256 `KEYRING_DEB_SHA256`, shipping `keys/pwsh-termux-archive-keyring.gpg` byte for byte;
3. `InRelease` and `Release.gpg` verify with `gpgv` against `keys/` alone, as apt will.

It then publishes that file unchanged. A secret replaced without changing `keys/`, or the reverse, publishes nothing.

This proves the keyring package was built by `build-packages.yaml` from the published commit, holds exactly the committed `keys/`, and that its online key signs the index. Whether `keys/` holds the *right* key rests on review of changes to `keys/` and on users comparing the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key).

## Testing

`KEYRING_FILE` overrides the key file and its markers, for tests with throwaway keys only ([build](../build.md#build-and-test-a-repository)); `update.yaml`'s signing step clears it. [`test-keys.sh`](../../../../scripts/test-keys.sh) tests every rule and refusal with throwaway keys and a stub `gh`; [`test-release-tags.sh`](../../../../scripts/test-release-tags.sh) tests the [release tags](../release.md#signed-release-tags), which the same online key signs.

## Rotation and recovery

apt accepts an index signed by any key in the `signed-by` file, and the keyring package is in that index, so new keys reach users through `pkg upgrade` while a key they already trust signs it:

1. **Planned rotation**: the next online key ships (marked by `keys/ROTATION`) while the current one still signs; the signer switches after a 180-day overlap ([release](../release.md#rotating-the-signing-key)).
2. **Lost or compromised online key**: the maintainer signs, offline with the recovery key that every installed keyring trusts, a repository whose keyring carries a new online key ([`recovery-sign.sh`](../../../../scripts/recovery-sign.sh)). [`recover.yaml`](../../../../.github/workflows/recover.yaml) holds no key and deploys only what [`verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) verifies against the recovery key alone ([release](../release.md#recovery-with-the-offline-key)). This needs `keys/RECOVERY` set up, and the hosting and the maintainer's GitHub account intact.

A manual keyring reinstall from the site is needed by:

1. a user who does not run `pkg upgrade` during the overlap or recovery window;
2. a user who added the key by hand;
3. everyone, if the online key is compromised and the recovery key is lost.

The first install rests on HTTPS, so the docs ask users to compare the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key) and offer `gh attestation verify` on the package.
