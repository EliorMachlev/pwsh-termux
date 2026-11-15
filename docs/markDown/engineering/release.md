# Release

There is nothing to "cut". The scheduled [`update.yaml`](../../../.github/workflows/update.yaml) picks up new PowerShell releases, and the same workflow publishes a change to this repository's scripts, keys or site on push to `main`. A published version is a Microsoft version plus a Debian revision ([packages](../product/packages.md#version-numbers)).

Run it by hand: **Actions → Update packages → Run workflow**, or `gh workflow run update.yaml`.

## Topics

1. [One-time setup](release/setup.md): the signing key, the `signing` environment, Pages, the custom domain.
2. [SBOMs, provenance and verification](release/provenance.md)
3. [Signed release tags](release/tags.md)
4. [Signing keys](release/signing-keys.md): rotation, the offline recovery key, recovery.
5. Related, under CI / CD: [rulesets and required checks](ci-cd/rulesets.md), [the keep-alive deploy key](ci-cd/keepalive.md#the-keep-alive-deploy-key), [when a run fails](ci-cd/troubleshooting.md).

## What happens on a run

1. `find-releases.sh` picks the stable release and, if newer, the preview ([releases](architecture/releases.md)).
2. `build-deb.sh` builds a `.deb` of each after verifying Microsoft's hash ([packaging](architecture/packaging.md)); `build-keyring.sh` builds `pwsh-termux-keyring` from `keys/` ([the keyring package](architecture/repository.md#the-keyring-package)). The same build writes the SBOMs and attests them ([provenance](release/provenance.md)).
3. The `verify` job (read-only token, no signing key) checks the keyring package's build provenance with `gh attestation verify`.
4. The `publish` job, which holds the signing key, runs `build-repo.sh`: it checks the key against `keys/` and the keyring package against the verified digest and `keys/`, writes the apt index and signs it. `assemble-site.sh` merges the website ([repository](architecture/repository.md), [hosting](architecture/hosting.md)).
5. In the same step, with the same key, `release-tags.sh` signs a tag `<package>-<version>` on the commit being published for each `pwsh` or `pwsh-preview` `.deb` that has none yet ([signed release tags](release/tags.md)).
6. Each such `.deb` not yet released becomes a GitHub release on its tag (pushed first, then `gh release create --verify-tag`), with the public key and the keyring package attached. A release is created once with all its files and never changed.
7. The result is deployed to Pages.

## Daily re-signing

The run happens **every day, release or not**, and makes no commit. The index carries a `Valid-Until` 14 days after its `Date` (`VALID_UNTIL_DAYS` in [`common.sh`](../../../scripts/lib/common.sh)), so apt refuses an index not re-signed for 14 days ([SECURITY.md](../../../SECURITY.md#index-freshness-valid-until)).

`build-deb.sh` and `build-keyring.sh` are reproducible, so an unchanged release rebuilds to the same bytes: `Packages`, `Packages.gz`, `Packages.xz` and every `.deb` stay identical, and only `Release`, `InRelease` and `Release.gpg` change. Clients re-download the small `InRelease` and are offered no upgrade. `test-keys.sh` proves it for the index; CI's package build builds the real `.deb` twice and compares.

**If the pipeline is broken for more than 14 days**, the index expires and `pkg update` fails on every device with *Release file … is expired*. That is deliberate: a loud error instead of silently frozen packages. Fix the run (or start it by hand); the next deploy clears it for everyone, with nothing to change on the devices. [`staleness.yaml`](../../../.github/workflows/staleness.yaml) checks the live index daily and opens an issue when fewer than 7 days are left. GitHub's 60-day pause of scheduled workflows is handled by the [schedule keep-alive](ci-cd/keepalive.md#schedule-keep-alive).

## If Microsoft publishes a bad release

There is no pin or skip list: the repository follows upstream. Wait for Microsoft's fix (the next daily run picks it up), or change `find-releases.sh` to skip that tag and push. Users who already upgraded can [go back](../product/packages.md#pinning-or-downgrading) to the previous build from its release asset.
