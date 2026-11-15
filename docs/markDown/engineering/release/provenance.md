# Release: SBOMs, provenance and verification

Part of the [release](../release.md) docs.

## SBOMs and provenance

[`build-packages.yaml`](../../../../.github/workflows/build-packages.yaml) is a reusable workflow that `update.yaml` calls. Each job holds only what it needs:

1. **`build`** builds the `.deb` files and writes their SBOMs with [`make-sboms.sh`](../../../../scripts/make-sboms.sh): CycloneDX 1.6 and three SPDX files, each from a different generator ([what they show](../../../../SECURITY.md#software-bill-of-materials-sbom-and-build-provenance)). No signing key, no token to sign provenance with.
2. **`attest`**, the only job with `id-token` and `attestations` write, attests the `.deb` files and the SBOMs with `actions/attest-build-provenance`, and keeps the bundle as a release file in the in-toto JSON Lines format, named as OpenSSF Scorecard's Signed-Releases check expects.
3. **`publish`** (in `update.yaml`), the only job with the apt signing key, builds the repository and attaches the `.deb`, its SBOMs, `SHA256SUMS`, the provenance and the public key to the release.

Every run builds and attests, not only for a new release; a release keeps the files of the build that created it. The keyring package goes through the same build, SBOMs and attestation, and the `verify` job checks its attestation before anything is signed.

Verify a release's files:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

The SBOM tools' versions and hashes are at the top of `make-sboms.sh`. Dependabot does not track them: update them by hand.

## Verifying a release by hand

`apt` checks the signed index and each package's SHA-256 for you. By hand, for a `.deb` from a release:

1. Compare `sha256sum <file>` with its `SHA256:` line in `https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages`.
2. Check the key's fingerprint against [SECURITY.md](../../../../SECURITY.md#signing-key).
3. Check the release's tag, signed with the same key: `git tag -v <tag>` ([signed release tags](tags.md)).

Failures of these steps in CI: [troubleshooting](../ci-cd/troubleshooting.md#provenance-and-signing).
