# Release

There is nothing to "cut". New PowerShell releases are picked up by the scheduled [`update.yaml`](../../../.github/workflows/update.yaml) workflow, and a change to this repository's scripts or site is published by the same workflow on push to `main`. A published version is a Microsoft version plus a Debian revision ([packages](../product/packages.md#version-numbers)).

## What happens on a run

1. `find-releases.sh` picks the stable and, if newer, the preview release ([releases](architecture/releases.md)).
2. `build-deb.sh` builds a `.deb` of each after verifying Microsoft's hash ([packaging](architecture/packaging.md)); `build-keyring.sh` builds `pwsh-termux-keyring` from `keys/` ([the keyring package](architecture/repository.md#the-keyring-package)).
3. `build-repo.sh`, in the job with the signing key, checks the key against `keys/`, rebuilds the keyring package and requires it to equal the attested one byte for byte and to contain the signing key, then writes the apt index and signs it; `assemble-site.sh` merges the website ([repository](architecture/repository.md), [hosting](architecture/hosting.md)).
4. Each `pwsh` or `pwsh-preview` `.deb` not yet released becomes a GitHub release, tagged `<package>-<version>`, with the public key and the keyring package attached. A release is created once with all its files and never changed afterwards.
5. The result is deployed to Pages.

Run it by hand: **Actions → Update packages → Run workflow**, or `gh workflow run update.yaml`.

## One-time setup

1. **Signing key.** Create a dedicated, passphrase-less Ed25519 key, keep the private half out of Git, and back it up outside GitHub (a GitHub secret cannot be read back):
   ```bash
   gpg --batch --passphrase '' --quick-generate-key "pwsh-termux <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <fingerprint> > signing-secret.asc
   gpg --export <fingerprint> > keys/pwsh-termux-archive-keyring.gpg     # public half only, binary
   bash scripts/check-keys.sh                                              # must list the fingerprint
   ```
   Commit `keys/pwsh-termux-archive-keyring.gpg`; `build-repo.sh` refuses to sign with a key that is not in it. Also create a revocation certificate (`gpg --gen-revoke`, which needs a terminal) and store it separately.
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

[`build-packages.yaml`](../../../.github/workflows/build-packages.yaml) is a reusable workflow that `update.yaml` calls. Its `build` job builds the `.deb` files and writes their SBOMs with [`scripts/make-sboms.sh`](../../../scripts/make-sboms.sh) (CycloneDX 1.6 and three SPDX files, each from a different generator; [what they show](../../../SECURITY.md#software-bill-of-materials-sbom-and-build-provenance)); it has no signing key and no token to sign provenance with. Its `attest` job (the only one with `id-token` and `attestations` write) attests the `.deb` files and the SBOMs with `actions/attest-build-provenance` and keeps the bundle as `pwsh-termux.intoto.jsonl`. `update.yaml`'s `publish` job, the only one with the apt signing key, then builds the repository and attaches the `.deb`, its SBOMs, `SHA256SUMS`, the provenance and the public key to the release.

A run builds and attests every day, not only for a new release; a release keeps the files of the build that created it. The keyring package goes through the same build, SBOMs and attestation; it is reproducible, so its attestation from any run of the same commit names the same bytes.

Verify with:

```bash
gh attestation verify pwsh_<version>_aarch64.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml
for f in pwsh_<version>_aarch64.*.json; do gh attestation verify "$f" --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml || break; done
```

If the publish job fails with "is not what build-keyring.sh builds", its rebuild of the keyring package differs from the attested one: a non-reproducible change to `build-keyring.sh` or its tools, or the two jobs dating it differently (both must check out the full history). Nothing is published; fix the cause, do not skip the check.

If CI fails in "Write the SBOMs", a tool's download or a validation failed: the log names the file. The tool versions and hashes are at the top of `make-sboms.sh`; Dependabot does not track them, so update them by hand.

## Verifying a release

`apt` verifies the signed index and each package's SHA-256 for you. By hand, for a `.deb` from a release: compare `sha256sum <file>` with its `SHA256:` line in `https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages`, and check the key's fingerprint against [SECURITY.md](../../../SECURITY.md#signing-key).

## If Microsoft publishes a bad release

There is no pin or skip list: the repository follows upstream. If a release is broken, wait for Microsoft's fix (the next daily run picks it up), or change `find-releases.sh` to skip that tag and push. Users who already upgraded can [go back](../product/packages.md#pinning-or-downgrading) to the previous build from its release asset.

## Rotating the signing key

apt accepts an index signed by any key in the `signed-by` file, and the keyring package delivers whatever is in `keys/`. A planned rotation therefore ships the next key first and signs with it later, so `pkg upgrade` carries users across:

1. **Add the next key.** Generate a new key as in step 1 of the setup (keep both secrets until the end). Append its public half: `gpg --export <new-fingerprint> >> keys/pwsh-termux-archive-keyring.gpg`, run `bash scripts/check-keys.sh` (two fingerprints), bump `KEYRING_VERSION` in `scripts/build-keyring.sh`, and list the new fingerprint in [`SECURITY.md`](../../../SECURITY.md#signing-key) as the next key. Merge: the repository is still signed with the **old** key, and `pkg upgrade` installs a keyring with both keys, as do new installs and `/pwsh-termux.gpg`.
2. **Wait about 60 days**, so that most users have run `pkg upgrade`.
3. **Switch the signing key.** `gh secret set GPG_PRIVATE_KEY < new-signing-secret.asc` and run the workflow. `build-repo.sh` accepts the new key because it is in `keys/` and so in the attested keyring package. Make the new fingerprint the current one in `SECURITY.md`, `docs/install.html`, the README and `docs/index.html` if it shows it. Users who did not upgrade the keyring in time see the signature fail and reinstall it with the install line.
4. **Drop the old key.** Rewrite the file with the new key only (`gpg --export <new-fingerprint> > keys/pwsh-termux-archive-keyring.gpg`), bump `KEYRING_VERSION` again, remove the old fingerprint from `SECURITY.md`, and destroy the old secret.

Users who added the key by hand download `https://pwsh-termux.machlev.org/pwsh-termux.gpg` again, any time between steps 1 and 3.

**If the key is compromised**, the steps above do not apply: whoever holds the old key could also sign a keyring of their own. Generate a new key, replace `keys/pwsh-termux-archive-keyring.gpg` with its public half only, bump `KEYRING_VERSION`, set the secret and run the workflow at once. Publish the old key's revocation certificate (`gpg --import revocation-cert.asc`, then export the revoked key and attach it to the advisory), update the fingerprint everywhere as in step 3, and announce it in a GitHub security advisory. Every user then reinstalls by hand: the install line again (it downloads the new `pwsh-termux-keyring.deb` from the site; `dpkg -i` replaces the old key file), after checking the new fingerprint against the advisory. Until they do, `pkg update` reports the repository's signature as invalid, which is the intended failure.

## Troubleshooting a failed run

See [CI / CD: when a run fails](ci-cd.md#when-a-run-fails).
