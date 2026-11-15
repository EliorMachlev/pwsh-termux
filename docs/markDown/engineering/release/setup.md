# Release: one-time setup

How the repository was set up, and where a fork or a rebuilt repository starts. Part of the [release](../release.md) docs.

## Steps

1. **Signing key.** A dedicated Ed25519 key with a random passphrase. Keep the private half out of Git and back up both halves outside GitHub (a GitHub secret cannot be read back):
   ```bash
   gpg --quick-generate-key "pwsh-termux <noreply@users.noreply.github.com>" ed25519 sign never   # asks for the passphrase
   gpg --armor --export-secret-keys <fingerprint> > signing-secret.asc   # still passphrase-protected
   gpg --export <fingerprint> > keys/pwsh-termux-archive-keyring.gpg     # public half only, binary
   bash scripts/check-keys.sh                                            # prints the fingerprint
   ```
   Commit `keys/pwsh-termux-archive-keyring.gpg`; `build-repo.sh` refuses to sign with any other key. Make a revocation certificate (`gpg --gen-revoke`, needs a terminal) and store it apart.
2. **Secrets, in the environment `signing`** ([below](#the-signing-environment)).
3. **Pages.** Settings → Pages → *Source: GitHub Actions*, or `gh api -X POST repos/EliorMachlev/pwsh-termux/pages -f build_type=workflow`.
4. **Run the workflow once**, then check the site.
5. **Custom domain** ([below](#custom-domain)).
6. **Private vulnerability reporting** on (Settings → Code security): [SECURITY.md](../../../../SECURITY.md) and `security.txt` point to it.
7. **Recovery key** ([signing keys](signing-keys.md#the-recovery-key)). Without it, a lost or compromised online key means every user reinstalls the keyring by hand.
8. **Immutable releases** (optional, recommended): Settings → General → *Releases* → *Enable release immutability*. A published release's tag and assets can then not be changed. The workflow is compatible: it creates each release once with all its files (`gh release create` uploads to a draft and publishes it at the end) and never uploads to an existing one. Whether it is on is not visible from the code.
9. **The keep-alive deploy key** and the [rulesets](../ci-cd/rulesets.md) that let it push to `main` only ([keep-alive deploy key](../ci-cd/keepalive.md#the-keep-alive-deploy-key)). In place, and the keep-alive commit verified end to end.

## The signing environment

`update.yaml`'s `publish` job is the only one that reads `GPG_PRIVATE_KEY` and `GPG_PASSPHRASE`. It runs in the environment `signing`, restricted to `main`, which holds both, so a run on any other branch cannot read them:

```bash
R=repos/EliorMachlev/pwsh-termux
gh api -X PUT $R/environments/signing --input - <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
gh api -X POST $R/environments/signing/deployment-branch-policies -f name=main -f type=branch
gh secret set GPG_PRIVATE_KEY --env signing < signing-secret.asc
gh secret set GPG_PASSPHRASE --env signing    # asks for the value; never put it on the command line
```

How the "Build the signed apt repository" step uses them:

1. Imports the key with `gpg --batch --import`.
2. Writes the passphrase to a mode-600 file under `RUNNER_TEMP` and passes it to `build-repo.sh` as `GPG_PASSPHRASE_FILE` (gpg reads it with `--pinentry-mode loopback --passphrase-file`, never from an argument).
3. Unsets both secrets before `build-repo.sh` runs, and removes the file when the step ends and again in an `always()` step.

Without `GPG_PASSPHRASE` a key with no passphrase still signs, with a warning; a protected key without its passphrase fails to sign, and nothing is published.

**Current state:** `signing` exists with the branch policy `main` and holds `GPG_PRIVATE_KEY` (passphrase-protected) and `GPG_PASSPHRASE`. `gh secret list` lists neither; `gh secret list --env signing` lists both. A job reads a repository secret when its environment has none of that name, so a repository secret `GPG_PRIVATE_KEY` must never come back: any branch could read it.

**What the passphrase is worth:** little. The workflow is unattended, so the passphrase sits in the same environment as the key, and whatever reads one reads the other. It only makes a leaked copy of the exported key alone (a backup, a stray `signing-secret.asc`) unusable. It is not a second factor.

**Adding a passphrase to a key that has none** (a key restored from an unprotected backup), on the machine holding the backup, outside GitHub:

1. `gpg --import signing-secret.asc`, then `gpg --passwd <fingerprint>` (a random passphrase).
2. `gpg --armor --export-secret-keys <fingerprint> > signing-secret.asc`.
3. `gh secret set GPG_PASSPHRASE --env signing` first, then `gh secret set GPG_PRIVATE_KEY --env signing < signing-secret.asc` (in between, the unprotected key still signs).
4. Run `update.yaml` by hand and check that it publishes without the *no passphrase* warning.

The fingerprint does not change, so `keys/` does not either.

## Custom domain

The site is served at `pwsh-termux.machlev.org`.

1. **DNS.** At the DNS provider for `machlev.org` (Cloudflare), add a `CNAME` record named `pwsh-termux` with target `eliormachlev.github.io`, **DNS only** (proxy off, grey cloud): GitHub has to see the record itself to issue the certificate.
2. **Set the domain** in the Pages settings, or `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -f cname=pwsh-termux.machlev.org`. Only **after** the record resolves: while the domain is set but unresolvable, the old `github.io` address redirects to a site nobody can reach.
3. **Enforce HTTPS** once GitHub shows the certificate as issued (minutes, up to an hour): `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -F https_enforced=true`.
4. **Verify the domain** in your GitHub account settings (Settings → Pages → *Add a domain*, a `TXT` record). It stops anyone else claiming the name for their own Pages site if the `CNAME` record is ever left dangling.

Check: `dig +short CNAME pwsh-termux.machlev.org` prints `eliormachlev.github.io.`.
