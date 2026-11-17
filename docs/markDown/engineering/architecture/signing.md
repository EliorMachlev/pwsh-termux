# Signing keys and publish checks

Which keys may sign the [apt index](repository.md#signing), what is checked before publishing, and how keys change. Procedures: [release](../release/signing-keys.md#rotating-the-signing-key).

## Key rules

[`check-keys.sh`](../../../../scripts/check-keys.sh) applies these in CI's `keys` job and every signing run, failing closed. [`keys/pwsh-termux-archive-keyring.gpg`](../../../../keys/pwsh-termux-archive-keyring.gpg) is binary OpenPGP with no secret material; `keys/` holds nothing else but two optional markers, each one 40-hex fingerprint:

1. `keys/RECOVERY` names the **recovery key**: offline, held only by the maintainer, never in GitHub or CI, used only after losing the online key. It must be in the keyring.
2. `keys/ROTATION` names the **next online key** during a planned rotation. It must be in the keyring and is not the recovery key.
3. Every other key is the **current online key**: exactly one.

Allowed shapes: `{current}`, `{current, recovery}`, `{current, next}`, `{current, next, recovery}`. A stray key, a marker naming a missing key, or a `ROTATION` marker whose key is the only online key left (stale) fails.

The signer must be the current key, or the next one while `ROTATION` exists. `build-repo.sh` refuses the recovery key, and refuses to sign at all if its secret is in the same gpg home. The key is Ed25519 (OpenPGP v4); fingerprint in [SECURITY.md](../../../../SECURITY.md#signing-key).

## Publish checks

[`update.yaml`](../../../../.github/workflows/update.yaml) runs them in three jobs:

1. **`verify`** (read-only token, no signing key) runs [`verify-attestation.sh`](../../../../scripts/verify-attestation.sh) on every `.deb` the build uploaded (the keyring package first): `gh attestation verify --repo EliorMachlev/pwsh-termux --signer-workflow …/build-packages.yaml --source-digest <this commit> --deny-self-hosted-runners`. It outputs the keyring package's SHA-256 and the SHA-256 of every `.deb`.
2. **`assemble`** (no key) runs `build-repo.sh` unsigned and writes the release tag payloads; `Release`, `Packages` and the payloads go to `sign` as a job output ([`signing-bundle.sh`](../../../../scripts/signing-bundle.sh)).
3. **`sign`** (the only job with the key, no `.deb`, no artifact access) runs [`sign-release.sh`](../../../../scripts/sign-release.sh) with the signing key and `KEYRING_DEB_SHA256` set to that digest, and `release-tags.sh sign-payloads` (which signs a tag payload only for a package and version that `Packages` lists, under the tag name its title gives). `publish` (no key) installs the signatures only if they verify (`sign-release.sh install`, `release-tags.sh assemble`).

`sign-release.sh` (given the `Release` and `Packages` files `build-repo.sh` wrote in `assemble`, never a `.deb`) refuses to sign unless:

1. `keys/` passes the key rules and the signing key is an allowed signer;
2. `Packages` holds exactly one `pwsh-termux-keyring` stanza, with a `SHA256` field equal to `KEYRING_DEB_SHA256` (the digest of the file `verify` attested);
3. `Packages` lists exactly the `.deb` files `verify` attested (`VERIFIED_DEB_SHA256S`): no other package and none missing, so the key never signs an index of a file with no verified provenance; and
4. `Release` is byte for byte what `write_release` (`scripts/lib/common.sh`) writes for that `Packages` (the signer rebuilds `Packages.gz` and `Packages.xz` from it) and `Release`'s own `Date`, which must be under a day old. So it has no repeated or extra field or section (apt reads the last `Valid-Until`, and any extra `SHA512:` section), and every digest in it is the index's own. `publish` makes the same comparison against the index it rebuilds (`sign-release.sh install`);
5. `InRelease` and `Release.gpg` verify with `gpgv` against `keys/` alone, as apt will.

It then publishes that file unchanged. A secret replaced without changing `keys/`, or the reverse, publishes nothing.

This proves the keyring package was built by `build-packages.yaml` from the published commit, holds exactly the committed `keys/`, and that its online key signs the index. Whether `keys/` holds the *right* key rests on review of changes to `keys/` and on users comparing the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key).

## Testing

`KEYRING_FILE` overrides the key file and its markers, for tests with throwaway keys only ([build](../build.md#build-and-test-a-repository)); `update.yaml`'s signing step clears it. [`test-keys.sh`](../../../../scripts/test-keys.sh) tests every rule and refusal with throwaway keys and a stub `gh`; [`test-release-tags.sh`](../../../../scripts/test-release-tags.sh) tests the [release tags](../release/tags.md), which the same online key signs; [`test-sign-release.sh`](../../../../scripts/test-sign-release.sh) tests the hand-off between `assemble`, `sign` and `publish`.

## Rotation and recovery

apt accepts an index signed by any key in the `signed-by` file, and the keyring package is in that index, so new keys reach users through `pkg upgrade` while a key they already trust signs it:

1. **Planned rotation**: the next online key ships (marked by `keys/ROTATION`) while the current one still signs; the signer switches after a 180-day overlap ([release](../release/signing-keys.md#rotating-the-signing-key)).
2. **Lost or compromised online key**: the maintainer signs, offline with the recovery key that every installed keyring trusts, a repository whose keyring carries a new online key ([`recovery-sign.sh`](../../../../scripts/recovery-sign.sh)). [`recover.yaml`](../../../../.github/workflows/recover.yaml) holds no key and deploys only what [`verify-recovery-repo.sh`](../../../../scripts/verify-recovery-repo.sh) verifies against the recovery key alone ([release](../release/signing-keys.md#recovery-with-the-offline-key)). This needs `keys/RECOVERY` set up, and the hosting and the maintainer's GitHub account intact.

A manual keyring reinstall from the site is needed by:

1. a user who does not run `pkg upgrade` during the overlap or recovery window;
2. a user who added the key by hand;
3. everyone, if the online key is compromised and the recovery key is lost.

The first install rests on HTTPS, so the docs ask users to compare the fingerprint with [SECURITY.md](../../../../SECURITY.md#signing-key) and offer `gh attestation verify` on the package.
