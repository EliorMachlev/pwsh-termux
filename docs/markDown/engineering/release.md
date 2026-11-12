# Release

There is nothing to "cut". New PowerShell releases are picked up by the scheduled [`update.yaml`](../../../.github/workflows/update.yaml) workflow, and a change to this repository's scripts or site is published by the same workflow on push to `main`. A published version is a Microsoft version plus a Debian revision ([packages](../product/packages.md#version-numbers)).

## What happens on a run

1. `find-releases.sh` picks the stable and, if newer, the preview release ([releases](architecture/releases.md)).
2. `build-deb.sh` builds a `.deb` of each after verifying Microsoft's hash ([packaging](architecture/packaging.md)); `build-keyring.sh` builds `pwsh-termux-keyring` from `keys/` ([the keyring package](architecture/repository.md#the-keyring-package)).
3. The `verify` job checks the keyring package's build provenance with `gh attestation verify` (read-only token, no signing key). Then `build-repo.sh`, in the job with the signing key, checks that key against `keys/` and the package against the verified digest and `keys/`, writes the apt index and signs it; `assemble-site.sh` merges the website ([repository](architecture/repository.md), [hosting](architecture/hosting.md)).
4. Each `pwsh` or `pwsh-preview` `.deb` not yet released becomes a GitHub release, tagged `<package>-<version>`, with the public key and the keyring package attached. A release is created once with all its files and never changed afterwards.
5. The result is deployed to Pages.

Run it by hand: **Actions → Update packages → Run workflow**, or `gh workflow run update.yaml`.

## One-time setup

1. **Signing key.** Create a dedicated, passphrase-less Ed25519 key, keep the private half out of Git, and back it up outside GitHub (a GitHub secret cannot be read back):
   ```bash
   gpg --batch --passphrase '' --quick-generate-key "pwsh-termux <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <fingerprint> > signing-secret.asc
   gpg --export <fingerprint> > keys/pwsh-termux-archive-keyring.gpg     # public half only, binary
   bash scripts/check-keys.sh                                              # prints the fingerprint
   ```
   Commit `keys/pwsh-termux-archive-keyring.gpg`; `build-repo.sh` refuses to sign with any other key. Also create a revocation certificate (`gpg --gen-revoke`, which needs a terminal) and store it separately.
2. **Secret.** `gh secret set GPG_PRIVATE_KEY < signing-secret.asc`.
3. **Pages.** Settings → Pages → *Source: GitHub Actions* (or `gh api -X POST repos/EliorMachlev/pwsh-termux/pages -f build_type=workflow`).
4. **Run the workflow once**, then check the site.
5. **Custom domain** ([below](#custom-domain)).
6. **Private vulnerability reporting** on (Settings → Code security), because [SECURITY.md](../../../SECURITY.md) and `security.txt` point to it.
7. **Immutable releases** (optional, recommended): Settings → General, *Releases* section, *Enable release immutability*. A published release's tag and assets can then no longer be changed or replaced. The workflow is compatible: it creates each release once with all its files (`gh release create` uploads to a draft and publishes it at the end) and never uploads to an existing release. This is a repository setting; whether it is on is not visible from the code.

## Custom domain

The site is served at `pwsh-termux.machlev.org`.

1. **DNS.** At the DNS provider for `machlev.org` (Cloudflare), add a record:

   | Type | Name | Target | Proxy |
   |---|---|---|---|
   | `CNAME` | `pwsh-termux` | `eliormachlev.github.io` | DNS only |

   Leave the proxy off (grey cloud): GitHub has to see the DNS record itself to issue the certificate.
2. **Set the domain** in the repository's Pages settings, or `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -f cname=pwsh-termux.machlev.org`. Do this **after** the DNS record resolves: while the domain is set but unresolvable, the old `github.io` address redirects to a site nobody can reach.
3. **Enforce HTTPS** once GitHub shows the certificate as issued (usually minutes; it can take up to an hour): `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -F https_enforced=true`.
4. **Verify the domain** in your GitHub account settings (Settings → Pages → *Add a domain*, a `TXT` record). It stops anyone else claiming `pwsh-termux.machlev.org` for their own Pages site if the `CNAME` record is ever left dangling.

Check from a shell: `dig +short CNAME pwsh-termux.machlev.org` should print `eliormachlev.github.io.`.

## SBOMs and provenance

[`build-packages.yaml`](../../../.github/workflows/build-packages.yaml) is a reusable workflow that `update.yaml` calls. Its `build` job builds the `.deb` files and writes their SBOMs with [`scripts/make-sboms.sh`](../../../scripts/make-sboms.sh) (CycloneDX 1.6 and three SPDX files, each from a different generator; [what they show](../../../SECURITY.md#software-bill-of-materials-sbom-and-build-provenance)); it has no signing key and no token to sign provenance with. Its `attest` job (the only one with `id-token` and `attestations` write) attests the `.deb` files and the SBOMs with `actions/attest-build-provenance` and keeps the bundle as a release file in the in-toto JSON Lines format, named the way OpenSSF Scorecard's Signed-Releases check expects. `update.yaml`'s `publish` job, the only one with the apt signing key, then builds the repository and attaches the `.deb`, its SBOMs, `SHA256SUMS`, the provenance and the public key to the release.

A run builds and attests every day, not only for a new release; a release keeps the files of the build that created it. The keyring package goes through the same build, SBOMs and attestation, and the `verify` job checks its attestation before anything is signed.

Verify with:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

If the `verify` job fails, the keyring package has no valid provenance from `build-packages.yaml` at this commit: nothing is signed or published. If `publish` fails in `build-repo.sh` with "is not the key in", the `GPG_PRIVATE_KEY` secret and `keys/` disagree (one was changed without the other, or `keys/ROTATION` is missing or stale). Fix the cause; do not skip the check.

If CI fails in "Write the SBOMs", a tool's download or a validation failed: the log names the file. The tool versions and hashes are at the top of `make-sboms.sh`; Dependabot does not track them, so update them by hand.

## Verifying a release

`apt` verifies the signed index and each package's SHA-256 for you. By hand, for a `.deb` from a release: compare `sha256sum <file>` with its `SHA256:` line in `https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages`, and check the key's fingerprint against [SECURITY.md](../../../SECURITY.md#signing-key).

## If Microsoft publishes a bad release

There is no pin or skip list: the repository follows upstream. If a release is broken, wait for Microsoft's fix (the next daily run picks it up), or change `find-releases.sh` to skip that tag and push. Users who already upgraded can [go back](../product/packages.md#pinning-or-downgrading) to the previous build from its release asset.

## Rotating the signing key

apt accepts an index signed by any key in the `signed-by` file, and the keyring package is part of the signed index. So a planned rotation reaches users through `pkg upgrade`, in four steps. The key rules ([repository](architecture/repository.md#signing)) allow a second key in `keys/` only while `keys/ROTATION` names it; CI and the publish job refuse anything else.

1. **Ship the next key** (a pull request). Generate the new key as in step 1 of the setup; keep both secrets. Append its public half and mark the rotation:
   ```bash
   gpg --export <new-fingerprint> >> keys/pwsh-termux-archive-keyring.gpg
   echo <NEW-FINGERPRINT> > keys/ROTATION            # 40 hex digits, upper case
   bash scripts/check-keys.sh                        # current + next
   ```
   Bump `KEYRING_VERSION` in `scripts/build-keyring.sh`, and add the new fingerprint to [`SECURITY.md`](../../../SECURITY.md#signing-key) as the next key. Merge. The **old** key still signs; the publish run puts a keyring with both keys in the index, and `pkg upgrade` installs it.
2. **Wait a grace period: 60 days is recommended**, so that users who upgrade rarely still receive step 1. Users who do not run `pkg upgrade` within it must reinstall the keyring by hand after step 3 (the install line), as must users who added the key by hand (download `/pwsh-termux.gpg` again).
3. **Switch the signer.** Replace the secret (`gh secret set GPG_PRIVATE_KEY < new-signing-secret.asc`) and, in the same step, merge a pull request that only makes the new fingerprint the current one in `SECURITY.md`, `docs/install.html`, the README and `docs/index.html` (it removes nothing from `keys/`). Check that the publish run succeeds signed by the new key: `keys/ROTATION` is still there and names the signer, which the rules allow.
4. **Drop the old key** (a pull request). `gpg --export <new-fingerprint> > keys/pwsh-termux-archive-keyring.gpg`, `git rm keys/ROTATION`, bump `KEYRING_VERSION` again, remove the old fingerprint from `SECURITY.md`. One key again; destroy the old secret.

**If the key is compromised**, none of this applies: whoever holds the old key could sign a keyring of their own, so a new key cannot ride on `pkg upgrade`. Generate a new key, replace `keys/pwsh-termux-archive-keyring.gpg` with its public half only (no `ROTATION`), bump `KEYRING_VERSION`, set the secret and run the workflow at once. Publish the old key's revocation certificate (`gpg --import revocation-cert.asc`, then export the revoked key and attach it to the advisory), update the fingerprint everywhere as in step 3, and announce it in a GitHub security advisory. Every user then reinstalls by hand: the install line again (it downloads the new `pwsh-termux-keyring.deb` from the site; `dpkg -i` replaces the old key file) and compares the new fingerprint with the advisory. Until they do, `pkg update` reports the repository's signature as invalid, which is the intended failure.

## Troubleshooting a failed run

See [CI / CD: when a run fails](ci-cd.md#when-a-run-fails).
