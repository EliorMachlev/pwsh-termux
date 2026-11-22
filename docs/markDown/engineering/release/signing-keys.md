# Release: signing keys, rotation and recovery

Part of the [release](../release.md) docs. The key rules are in [repository: signing](../architecture/repository.md#signing): `keys/` holds one online key, plus the recovery key if `keys/RECOVERY` names it, plus a next online key only while `keys/ROTATION` names it. CI and the publish job refuse anything else.

apt accepts an index signed by any key in the `signed-by` file, and the keyring package is part of the signed index. That is what lets a new key reach users through `pkg upgrade`.

## Rotating the signing key

A planned rotation, in four steps. The recovery key, if set up, stays in `keys/` throughout.

1. **Ship the next key** (a pull request). Generate it as in [setup](setup.md#steps) step 1; keep both secrets. Append its public half and mark the rotation:
   ```bash
   gpg --export <new-fingerprint> >> keys/pwsh-termux-archive-keyring.gpg
   echo <NEW-FINGERPRINT> > keys/ROTATION            # 40 hex digits, upper case
   bash scripts/check-keys.sh                        # current, next (and recovery)
   ```
   Bump `KEYRING_VERSION` in `scripts/build-keyring.sh`, and add the new fingerprint to [SECURITY.md](../../../../SECURITY.md#signing-key) as the next key. Merge. The **current** key still signs; the next publish run puts a keyring with both online keys in the index, and `pkg upgrade` installs it.
2. **Overlap: 180 days**, so that a phone whose Termux goes unused for months still receives step 1. Waiting costs nothing: the rotation is planned and the current key is not suspect. The overlap is state (`keys/ROTATION` stays committed until step 4), not a timer: nothing happens when it ends until the maintainer does step 3.
3. **Switch the signer.** Replace the secrets (`gh secret set GPG_PRIVATE_KEY --env signing < new-signing-secret.asc`, and `gh secret set GPG_PASSPHRASE --env signing` with the new key's passphrase) and, at the same time, merge a pull request that only makes the new fingerprint the current one in `SECURITY.md`, `docs/verify.html`, `INSTALL.md` and `docs/llms.txt` (it removes nothing from `keys/`). Check that the publish run succeeds signed by the new key: `keys/ROTATION` still names the signer, which the rules allow.
4. **Drop the old key** (a pull request). `gpg --export <new-fingerprint> [<recovery-fingerprint>] > keys/pwsh-termux-archive-keyring.gpg`; `git rm keys/ROTATION`; bump `KEYRING_VERSION` again; remove the old fingerprint from `SECURITY.md`. Destroy the old secret.

A user who did not run `pkg upgrade` during the overlap, or who added the key by hand, reinstalls the keyring from the site after step 3.

## The recovery key

An offline Ed25519 key that only the maintainer holds, never on a networked machine, in GitHub or in CI. Its public half is in every installed keyring, so it can sign the way out of a lost or compromised online key ([below](#recovery-with-the-offline-key)). It signs nothing else: `sign-release.sh` and `release-tags.sh` refuse it as a signer and refuse to sign if its secret is in the gpg home.

**It is set up**: its fingerprint is in `keys/RECOVERY` and [SECURITY.md](../../../../SECURITY.md#signing-key). The code still accepts `keys/` without one, as a fork or a rebuilt repository would start. The steps below are how it was made and how to replace it. Never generate it on a phone or on any online machine.

1. **Generate it offline**, on a machine that is not and will not be connected to a network (a live system booted without networking is enough), with a strong passphrase:
   ```bash
   gpg --quick-generate-key "pwsh-termux recovery key <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <recovery-fingerprint> > recovery-secret.asc     # passphrase-protected
   gpg --gen-revoke <recovery-fingerprint> > recovery-revoke.asc
   gpg --export <recovery-fingerprint> > recovery-public.gpg                          # the only file that leaves
   ```
2. **Store it.** `recovery-secret.asc` on at least two offline media in different places (for example two encrypted USB drives, or one plus a paper copy made with `paperkey`); `recovery-revoke.asc` apart from both; the passphrase written down apart from the media. Never copy the secret to an online machine, a cloud drive, a syncing password manager or a GitHub secret.
3. **Add it** (a pull request). Append `recovery-public.gpg` to `keys/pwsh-termux-archive-keyring.gpg`, `echo <RECOVERY-FINGERPRINT> > keys/RECOVERY`, bump `KEYRING_VERSION`, add a *Recovery key* row with its fingerprint to [SECURITY.md](../../../../SECURITY.md#signing-key) (CI checks it is there), and run `bash scripts/check-keys.sh` (`current`, `recovery`). From the next publish on, `pkg upgrade` gives every user a keyring that trusts it.

Every 2 January [`key-review.yaml`](../../../../.github/workflows/key-review.yaml) opens an issue reminding the maintainer to check these backups (offline, by hand) and review the rotation plan. The issue holds no key material.

## Recovery with the offline key

For a compromised or lost online key. It needs the recovery key, and an intact hosting (GitHub Pages, the domain) and maintainer account: the recovery key replaces only the online key. With the online key compromised **and** the recovery key lost (or never set up), every user reinstalls the keyring from the site after an advisory.

1. **Stop the online key.** `gh secret delete GPG_PRIVATE_KEY --env signing`, `gh secret delete GPG_PASSPHRASE --env signing`, `gh workflow disable update.yaml`. A workflow disabled by hand stays off: the [schedule keep-alive](../ci-cd/keepalive.md#schedule-keep-alive) re-enables only what GitHub disabled for inactivity. Publish a GitHub security advisory; if the key was compromised, attach its revocation certificate.
2. **New online key** (a pull request). Generate it as in [setup](setup.md#steps) step 1 (do not set the secret yet). Write `keys/pwsh-termux-archive-keyring.gpg` as the new online key plus the recovery key, `keys/RECOVERY` unchanged, no `ROTATION`; bump `KEYRING_VERSION`; make the new fingerprint the current one in `SECURITY.md` and the pages. Merge (nothing is published: the pipeline is disabled).
3. **Build and sign offline**, from that commit, on the machine with the recovery key. Bring in the current `pwsh`/`pwsh-preview` `.deb` files from their releases (check them with `gh attestation verify` first, on an online machine), then:
   ```bash
   bash scripts/build-keyring.sh debs                 # the new keyring, from keys/
   bash scripts/build-repo.sh debs repo               # unsigned
   bash scripts/recovery-sign.sh repo                 # signs with the recovery key, then verifies
   tar -czf recovery-repo.tar.gz -C repo .
   ```
   `build-repo.sh` writes `Release` with a `Valid-Until` 14 days ahead; `recovery-sign.sh` refuses one with fewer than 7 days left or a longer window.
4. **Deploy it** (online again): `gh release create recovery-<date> recovery-repo.tar.gz --latest=false --title "Recovery <date>" --notes "Repository signed with the recovery key; see the advisory."`, then `gh workflow run recover.yaml -f tag=recovery-<date>`. `recover.yaml` holds no signing key. It deploys only if `verify-recovery-repo.sh` finds:
   - `InRelease` and `Release.gpg` signed by the recovery key alone;
   - a `Valid-Until` at most 14 days after `Date`, with at least 7 days left;
   - `Release`, `Packages` and every `.deb` in `pool/` consistent;
   - the key files equal to `keys/`.

   It takes the public key files and the website from the commit, not from the tarball. Required reviewers on the `github-pages` environment (Settings → Environments) would add a second confirmation.
5. **Users** run `pkg upgrade` as usual: apt accepts the index because it trusts the recovery key, and installs the keyring with the new online key in place of the old one. Nothing manual.
6. **Recovery window: 180 days**, as for a rotation. Leave the pipeline disabled. Nothing online can re-sign the recovery-signed index, which expires 14 days after `build-repo.sh` wrote it, so **repeat steps 3 and 4 at least every 14 days** (weekly is comfortable) and for each new PowerShell release. Run `build-repo.sh` and `recovery-sign.sh` in one sitting: both `recovery-sign.sh` and `recover.yaml` refuse a `Release` with fewer than 7 days left.
7. **Back to normal.** `gh secret set GPG_PRIVATE_KEY --env signing < new-signing-secret.asc`, `gh secret set GPG_PASSPHRASE --env signing` (its passphrase), `gh workflow enable update.yaml`. The online key signs again. A user who did not run `pkg upgrade` in the window reinstalls the keyring from the site.

Until a user upgrades, whoever holds a compromised key can still sign an index that user accepts, though serving it to them takes control of their connection or of the hosting.
