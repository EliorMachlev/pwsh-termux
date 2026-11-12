# Release

There is nothing to "cut". New PowerShell releases are picked up by the scheduled [`update.yaml`](../../../.github/workflows/update.yaml) workflow, and a change to this repository's scripts or site is published by the same workflow on push to `main`. A published version is a Microsoft version plus a Debian revision ([packages](../product/packages.md#version-numbers)).

## What happens on a run

1. `find-releases.sh` picks the stable and, if newer, the preview release ([releases](architecture/releases.md)).
2. `build-deb.sh` builds a `.deb` of each after verifying Microsoft's hash ([packaging](architecture/packaging.md)).
3. `build-repo.sh` writes the apt index and signs it; `assemble-site.sh` merges the website ([repository](architecture/repository.md), [hosting](architecture/hosting.md)).
4. Each `.deb` not yet released becomes a GitHub release, tagged `<package>-<version>`.
5. The result is deployed to Pages.

Run it by hand: **Actions → Update packages → Run workflow**, or `gh workflow run update.yaml`.

## One-time setup

1. **Signing key.** Create a dedicated, passphrase-less Ed25519 key, keep the private half out of Git, and back it up outside GitHub (a GitHub secret cannot be read back):
   ```bash
   gpg --batch --passphrase '' --quick-generate-key "pwsh-termux <noreply@users.noreply.github.com>" ed25519 sign never
   gpg --armor --export-secret-keys <fingerprint> > signing-secret.asc
   ```
   Also create a revocation certificate (`gpg --gen-revoke`, which needs a terminal) and store it separately.
2. **Secret.** `gh secret set GPG_PRIVATE_KEY < signing-secret.asc`.
3. **Pages.** Settings → Pages → *Source: GitHub Actions* (or `gh api -X POST repos/EliorMachlev/pwsh-termux/pages -f build_type=workflow`).
4. **Run the workflow once**, then check the site.
5. **Custom domain** ([below](#custom-domain)).
6. **Private vulnerability reporting** on (Settings → Code security), because [SECURITY.md](../../../SECURITY.md) and `security.txt` point to it.

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

## Verifying a release

`apt` verifies the signed index and each package's SHA-256 for you. By hand, for a `.deb` from a release: compare `sha256sum <file>` with its `SHA256:` line in `https://pwsh-termux.machlev.org/dists/stable/main/binary-aarch64/Packages`, and check the key's fingerprint against [SECURITY.md](../../../SECURITY.md#signing-key).

## If Microsoft publishes a bad release

There is no pin or skip list: the repository follows upstream. If a release is broken, wait for Microsoft's fix (the next daily run picks it up), or change `find-releases.sh` to skip that tag and push. Users who already upgraded can [go back](../product/packages.md#pinning-or-downgrading) to the previous build from its release asset.

## Rotating the signing key

Do this on a schedule you are comfortable with, and at once if the key may be exposed.

1. Generate a new key as in step 1 of the setup; keep the old key's secret until the switch is done.
2. Replace the `GPG_PRIVATE_KEY` secret and run the workflow: the repository is now signed by the new key and publishes it as `pwsh-termux.gpg`.
3. Update the fingerprint in [`SECURITY.md`](../../../SECURITY.md), `docs/install.html`, the README and the `docs/` page, and announce the change in a GitHub security advisory.
4. Users replace the key file in `$PREFIX/etc/apt/trusted.gpg.d/`. Until they do, `pkg update` reports the repository's signature as invalid, which is the intended failure.
5. If the old key was compromised, publish its revocation certificate (`gpg --import revocation-cert.asc`, then export and publish the key).

## Troubleshooting a failed run

See [CI / CD: when a run fails](ci-cd.md#when-a-run-fails).
