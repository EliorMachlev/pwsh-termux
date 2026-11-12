# Release

There is nothing to "cut". New PowerShell releases are picked up by the scheduled [`update.yaml`](../../../.github/workflows/update.yaml) workflow, and a change to this repository's scripts or site is published by the same workflow on push to `main`. A published version is a Microsoft version plus a Debian revision ([packages](../product/packages.md#version-numbers)).

## What happens on a run

1. `find-releases.sh` picks the stable and, if newer, the preview release ([releases](architecture/releases.md)).
2. `build-deb.sh` builds a `.deb` of each after verifying Microsoft's hash ([packaging](architecture/packaging.md)); `build-keyring.sh` builds `pwsh-termux-keyring` from `keys/` ([the keyring package](architecture/repository.md#the-keyring-package)).
3. The `verify` job checks the keyring package's build provenance with `gh attestation verify` (read-only token, no signing key). Then `build-repo.sh`, in the job with the signing key, checks that key against `keys/` and the package against the verified digest and `keys/`, writes the apt index and signs it; `assemble-site.sh` merges the website ([repository](architecture/repository.md), [hosting](architecture/hosting.md)).
4. Each `pwsh` or `pwsh-preview` `.deb` not yet released becomes a GitHub release, tagged `<package>-<version>`, with the public key and the keyring package attached. A release is created once with all its files and never changed afterwards.
5. The result is deployed to Pages.

This happens **every day, whether or not Microsoft released anything**, and makes no commit. The index carries a `Valid-Until` 14 days after its `Date` (`VALID_UNTIL_DAYS` in [`scripts/lib/common.sh`](../../../scripts/lib/common.sh)), so apt refuses an index that has not been re-signed for 14 days ([SECURITY.md](../../../SECURITY.md#index-freshness-valid-until)); the daily run is what moves that date on. An unchanged release rebuilds to the same bytes (`build-deb.sh` and `build-keyring.sh` are reproducible), so `Packages`, `Packages.gz`, `Packages.xz` and every `.deb` are byte-identical from one day to the next and only `Release`, `InRelease` and `Release.gpg` change: clients re-download the small `InRelease` and are offered no upgrade. `test-keys.sh` proves it for the index, and CI's package build builds the real `.deb` twice and compares.

**If the pipeline is broken for more than 14 days**, the deployed index expires and `pkg update` on every device fails with *Release file … is expired*. That is deliberate: a loud error instead of silently frozen packages. Fix the run (or start it by hand) and the next deploy clears it for everyone; nothing needs to change on the devices. [`staleness.yaml`](../../../.github/workflows/staleness.yaml) checks the live index daily and opens an issue when fewer than 7 days are left, so this should be caught a week early. GitHub's 60-day pause of scheduled workflows in an inactive repository is handled by the [schedule keep-alive](ci-cd.md#schedule-keep-alive).

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
7. **Recovery key** (recommended; [below](#the-recovery-key)). It is set up; without it a compromised or lost online key would mean every user reinstalls the keyring by hand.
8. **Immutable releases** (optional, recommended): Settings → General, *Releases* section, *Enable release immutability*. A published release's tag and assets can then no longer be changed or replaced. The workflow is compatible: it creates each release once with all its files (`gh release create` uploads to a draft and publishes it at the end) and never uploads to an existing release. This is a repository setting; whether it is on is not visible from the code.

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

apt accepts an index signed by any key in the `signed-by` file, and the keyring package is part of the signed index. So a planned rotation reaches users through `pkg upgrade`, in four steps. The key rules ([repository](architecture/repository.md#signing)) allow a second online key in `keys/` only while `keys/ROTATION` names it; CI and the publish job refuse anything else. The recovery key, if set up, stays in `keys/` throughout.

1. **Ship the next key** (a pull request). Generate the new key as in step 1 of the setup; keep both secrets. Append its public half and mark the rotation:
   ```bash
   gpg --export <new-fingerprint> >> keys/pwsh-termux-archive-keyring.gpg
   echo <NEW-FINGERPRINT> > keys/ROTATION            # 40 hex digits, upper case
   bash scripts/check-keys.sh                        # current, next (and recovery)
   ```
   Bump `KEYRING_VERSION` in `scripts/build-keyring.sh`, and add the new fingerprint to [`SECURITY.md`](../../../SECURITY.md#signing-key) as the next key. Merge. The **current** key still signs; the publish run puts a keyring with both online keys in the index, and `pkg upgrade` installs it.
2. **Overlap: 180 days.** A user who runs `pkg upgrade` at any time in this window receives step 1. 180 days rather than a few weeks because a phone's Termux may go unused for months, and nothing is lost by waiting: the rotation is planned, the current key is not suspect. The overlap is state in the repository (`keys/ROTATION` stays committed until step 4), not a timer: nothing happens on its own when it ends; the maintainer does step 3.
3. **Switch the signer.** Replace the secret (`gh secret set GPG_PRIVATE_KEY < new-signing-secret.asc`) and, at the same time, merge a pull request that only makes the new fingerprint the current one in `SECURITY.md`, `docs/install.html`, the README and `docs/index.html` (it removes nothing from `keys/`). Check that the publish run succeeds signed by the new key: `keys/ROTATION` is still there and names the signer, which the rules allow.
4. **Drop the old key** (a pull request). Rewrite `keys/pwsh-termux-archive-keyring.gpg` with the new online key (and the recovery key, if any): `gpg --export <new-fingerprint> [<recovery-fingerprint>] > keys/pwsh-termux-archive-keyring.gpg`; `git rm keys/ROTATION`; bump `KEYRING_VERSION` again; remove the old fingerprint from `SECURITY.md`. Destroy the old secret.

A user who did not run `pkg upgrade` during the overlap, or who added the key by hand, has to reinstall the keyring from the site after step 3.

## The recovery key

An offline Ed25519 key that only the maintainer holds, never on a networked machine, in GitHub or in CI. Its public half is in every installed keyring, so it can sign the way out of a lost or compromised online key ([below](#recovery-with-the-offline-key)). It never signs the repository otherwise: `build-repo.sh` refuses it as a signer and refuses to sign if its secret is in the gpg home.

**It is set up**: its fingerprint is in `keys/RECOVERY` and [SECURITY.md](../../../SECURITY.md#signing-key). The code still accepts `keys/` without a recovery key, which is how a fork or a rebuilt repository would start. The steps below are how it was made and how to replace it. Do not generate one on a phone or on any machine that is online.

1. **Generate it offline**, on a machine that is not and will not be connected to a network (a live system booted without networking is enough), with a strong passphrase:
   ```bash
   gpg --quick-generate-key "pwsh-termux recovery key <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <recovery-fingerprint> > recovery-secret.asc     # passphrase-protected
   gpg --gen-revoke <recovery-fingerprint> > recovery-revoke.asc
   gpg --export <recovery-fingerprint> > recovery-public.gpg                          # the only file that leaves
   ```
2. **Store it**: `recovery-secret.asc` on at least two offline media kept in different places (for example two encrypted USB drives, or one plus a paper copy made with `paperkey`); `recovery-revoke.asc` separately from both; the passphrase written down apart from the media. Never copy the secret to an online machine, a cloud drive, a password manager that syncs, or a GitHub secret.
3. **Add it** (a pull request): append `recovery-public.gpg` to `keys/pwsh-termux-archive-keyring.gpg`, `echo <RECOVERY-FINGERPRINT> > keys/RECOVERY`, bump `KEYRING_VERSION`, add a *Recovery key* row with its fingerprint to [`SECURITY.md`](../../../SECURITY.md#signing-key) (CI checks it is there), and run `bash scripts/check-keys.sh` (`current`, `recovery`). From the next publish on, `pkg upgrade` gives every user a keyring that trusts it.

Once a year [`key-review.yaml`](../../../.github/workflows/key-review.yaml) opens an issue reminding you to check these backups (offline, by hand) and to review the rotation plan above; the issue holds no key material.

## Recovery with the offline key

When the online key is compromised or lost. It needs the recovery key to be set up, and it needs the hosting (GitHub Pages and the domain) and the maintainer's GitHub account to be intact: the recovery key only replaces the online key, nothing else. With the online key compromised **and** the recovery key lost (or never set up), there is no way around it: every user reinstalls the keyring from the site after an advisory.

1. **Stop the online key.** `gh secret delete GPG_PRIVATE_KEY` and `gh workflow disable update.yaml`. A workflow disabled by hand stays off: the [schedule keep-alive](ci-cd.md#schedule-keep-alive) re-enables only what GitHub disabled for inactivity. Publish a GitHub security advisory; if the key was compromised, attach its revocation certificate.
2. **New online key** (a pull request). Generate it as in step 1 of the setup (do not set the secret yet). Write `keys/pwsh-termux-archive-keyring.gpg` as the new online key plus the recovery key, with `keys/RECOVERY` unchanged and no `ROTATION`; bump `KEYRING_VERSION`; make the new fingerprint the current one in `SECURITY.md` and the pages. Merge (nothing is published: the pipeline is disabled).
3. **Build and sign offline**, from that commit, on the machine with the recovery key. Bring in the current `pwsh`/`pwsh-preview` `.deb` files from their releases (check them with `gh attestation verify` first, on an online machine), then:
   ```bash
   bash scripts/build-keyring.sh debs                 # the new keyring, from keys/
   bash scripts/build-repo.sh debs repo               # unsigned
   bash scripts/recovery-sign.sh repo                 # signs with the recovery key, then verifies
   tar -czf recovery-repo.tar.gz -C repo .
   ```
   `build-repo.sh` writes `Release` with a `Valid-Until` 14 days ahead; `recovery-sign.sh` refuses to sign one with fewer than 7 days left or a longer window.
4. **Deploy it** (online again): `gh release create recovery-<date> recovery-repo.tar.gz --latest=false --title "Recovery <date>" --notes "Repository signed with the recovery key; see the advisory."`, then `gh workflow run recover.yaml -f tag=recovery-<date>`. The workflow has no signing key: it deploys only if `verify-recovery-repo.sh` finds `InRelease` and `Release.gpg` signed by the recovery key alone, a `Valid-Until` at most 14 days after `Date` with at least 7 days left, `Release`, `Packages` and every `.deb` in `pool/` consistent, and the key files equal to `keys/`; it takes the public key files and the website from the commit, not from the tarball. Adding required reviewers to the `github-pages` environment (Settings → Environments) puts a second confirmation in front of it.
5. **Users** run `pkg upgrade` as usual: apt accepts the index because it trusts the recovery key, and installs the keyring with the new online key in place of the old one. Nothing manual.
6. **Recovery window: 180 days**, as for a rotation. Leave the pipeline disabled. The recovery-signed index expires 14 days after `build-repo.sh` wrote it (`Valid-Until`), and nothing online can re-sign it, so **repeat steps 3 and 4 at least every 14 days** (weekly is comfortable), and for a new PowerShell release. `recovery-sign.sh` refuses a `Release` with fewer than 7 days left (run `build-repo.sh` and it in one sitting), and `recover.yaml` refuses to deploy one.
7. **Back to normal.** `gh secret set GPG_PRIVATE_KEY < new-signing-secret.asc` and `gh workflow enable update.yaml`. From now on the online key signs again. A user who did not run `pkg upgrade` in the window reinstalls the keyring from the site.

Until a user upgrades, whoever holds a compromised key can still sign an index that user accepts, though serving it to them takes control of their connection or of the hosting.

## Troubleshooting a failed run

See [CI / CD: when a run fails](ci-cd.md#when-a-run-fails).
