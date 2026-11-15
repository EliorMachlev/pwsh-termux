# Assurance case

**Claim:** a user who installs `pwsh` with `pkg` gets Microsoft's PowerShell, built by this repository's pipeline from a Microsoft release, and nothing else.

1. **The input is Microsoft's.** The build downloads only from Microsoft's GitHub releases and stops unless the tarball matches Microsoft's `hashes.sha256` ([packaging](../architecture/packaging.md)). The only edits are listed in [NOTICE.md](../../../../NOTICE.md).
2. **The build is the repository's.** Packages are built twice in a job without secrets, and the bytes compared. Build provenance is attested, and a second job verifies it before anything is signed ([repository](../architecture/repository.md#signing)).
3. **The code is controlled.** Nothing reaches `main` except through a pull request that passes 19 required checks (DCO sign-off, static analysis, tests with a coverage floor, fuzzing, secret scanning, spelling, links, a package build) on signed commits. An audit checks every commit on `main` afterwards ([threat model](threat-model.md#malicious-change-to-the-workflows-or-scripts), [audit](../ci-cd/audit.md)).
4. **The delivery is signed.** apt verifies an Ed25519 signature on the index, then each file's hash, over HTTPS. The index expires after 14 days, which bounds a replay or a frozen repository ([threat model](threat-model.md#frozen-or-replayed-index)).
5. **The signing key is protected and recoverable.** It exists only in an environment that `main` alone can use; there is an offline recovery key and a documented rotation ([threat model](threat-model.md#signing-key-theft)).

**Accepted weaknesses:**

- A compromised upstream release would be packaged.
- The maintainer's account and the keep-alive deploy key can change `main`.
- There is one maintainer ([governance](../governance.md#continuity)).

The [threat model](threat-model.md) says what limits each.
