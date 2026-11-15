# Threat model

What must not happen: a user installs a package that is not Microsoft's PowerShell as built by this pipeline. Each threat lists its mitigation and what is left over.

## Tampered download

The tarball changes between Microsoft and the build.

- **Mitigation.** Each tarball must match Microsoft's `hashes.sha256` for that release, or the build stops ([packaging](../architecture/packaging.md)).
- **Left over.** Both files come from the same release, so a compromised upstream release would be packaged.

## Tampered package or index

- **Mitigation.** apt checks the Ed25519 signature on `InRelease`, then each index file's hash, then each `.deb`'s SHA-256, over HTTPS.
- **Left over.** Whoever holds the signing key can sign anything ([signing key theft](#signing-key-theft)).

## Frozen or replayed index

An old, validly signed index is served again to hide an update.

- **Mitigation.** `Release` carries `Valid-Until` = `Date` + 14 days, and the daily run re-signs it without a commit. `verify-recovery-repo.sh` and `recovery-sign.sh` refuse a window longer than 14 days or with fewer than 7 left. [`staleness.yaml`](../../../../.github/workflows/staleness.yaml) checks the live index daily (reachable, signed by a key in `keys/`, at least 7 days left) and opens an issue otherwise.
- **Left over.** A replay within the 14 days is accepted. A pipeline broken for longer makes `pkg update` fail with *expired* for every user until the index is re-signed ([SECURITY.md](../../../../SECURITY.md#index-freshness-valid-until)).

## Schedules disabled for inactivity

GitHub disables a public repository's schedules after 60 days without activity, which stops the daily re-sign; 14 days later the index expires.

- **Mitigation.** `update.yaml`, `staleness.yaml` (daily) and `keepalive.yaml` (twice a week) re-enable every scheduled workflow through the REST API with their own `GITHUB_TOKEN`, each renewing the others; a workflow turned off by hand stays off ([keep-alive](../ci-cd/keepalive.md#schedule-keep-alive)). `staleness.yaml` opens an issue for a workflow in `disabled_inactivity`. GitHub documents only commits as activity, so [`keepalive-commit.yaml`](../../../../.github/workflows/keepalive-commit.yaml) pushes a commit that only sets `keep.alive` once `main` has been quiet for 30 days, with the deploy key below ([keep-alive commit](../ci-cd/keepalive.md#keep-alive-commit)).
- **Left over.** GitHub does not document that re-enabling restarts the 60-day count; the keep-alive commit covers that. If it fails too, every schedule stops on day 60 and the maintainer has the index's 14 days to restart them.

## Leaked keep-alive deploy key

- **Mitigation.**
  - The key is the secret `KEEPALIVE_DEPLOY_KEY` of the environment `keepalive` (`main` only). The job refuses any other ref, runs only `keepalive-commit.sh`, keeps the key in an `ssh-agent` and pins GitHub's host key. The script pushes only a one-parent commit that changes only `keep.alive`, as `github-actions[bot]`.
  - Deploy keys bypass only *Main*'s signature, code-scanning, pull-request and status-check rules, never *Protection*'s deletion, force-push or branch-creation rules ([rulesets](../ci-cd/rulesets.md)). The bypass covers every deploy key, so exactly one exists.
  - [`audit-main.yaml`](../../../../.github/workflows/audit-main.yaml) checks every commit on `main` on each push and daily ([audit](../ci-cd/audit.md)). It accepts verified commits by the owner, verified `web-flow` merge commits of merged pull requests, and valid keep-alive commits with the `keepalive/pushed` status, which only a workflow's `GITHUB_TOKEN` can set. Anything else opens an issue to rotate the key ([rotation](../ci-cd/keepalive.md#rotating-the-keep-alive-deploy-key)).
- **Left over.** The holder can push any fast-forward commit to `main`, including a workflow change that reads the `signing` secrets: treat a leaked deploy key as a leaked signing key ([recovery](../release/signing-keys.md#recovery-with-the-offline-key)). The audit detects within a day but does not prevent, and the same push can change it. The key could also create a tag on an existing signed commit (*Tag Protection* has no `creation` rule), and create, force-push or delete a branch under `dependabot/`, which *Protection* excludes; a push to an open Dependabot pull request's branch changes what it would merge, so read its diff before merging ([Dependabot's branches](../ci-cd/rulesets.md)). GitHub cannot limit a bypass to one file; the guard is in the script.

## Signing key theft

- **Mitigation.** The key is a secret of the environment `signing` (`main` only), used in one step that signs the index and release tags, and never written to `GITHUB_ENV`, an output, an artifact or the log. A copy and a revocation certificate are held outside GitHub. [Rotation](../release/signing-keys.md#rotating-the-signing-key) is documented, and the offline [recovery key](../release/signing-keys.md#recovery-with-the-offline-key) moves users to a new key through `pkg upgrade`.
- **Left over.** The passphrase is in the same environment (the workflow is unattended), so it protects only a copy of the key on its own. No hardware token. If the recovery key is lost too, every user must reinstall the keyring by hand.

## Forged or moved release tag

- **Mitigation.** Each release sits on an annotated tag signed with the online key, on the commit that built it. [`release-tags.sh`](../../../../scripts/release-tags.sh) makes it in the signing step and checks it with `gpgv` against `keys/` before the push; `gh release create --verify-tag` refuses a missing tag. *Tag Protection* forbids moving or deleting tags, and releases are immutable. Users check with `git tag -v` ([SECURITY.md](../../../../SECURITY.md#verifying-a-release-tag), [signed release tags](../release/tags.md)).
- **Left over.** GitHub does not verify tag signatures on push. Anyone with the signing key or tag write access can create a new tag name.

## Wrong key in the keyring package

- **Mitigation.** `keys/` holds exactly one online key plus only keys named by `keys/RECOVERY` or `keys/ROTATION`; `check-keys.sh` enforces it in CI and the publish job. The package is attested in the unprivileged build job, a job without the signing key verifies the attestation, and the publish job signs only that verified file, only if it ships `keys/` byte for byte and the signer is the online key ([repository](../architecture/repository.md#signing)).
- **Left over.** That the committed keys are the right ones rests on review of `keys/` and on users comparing fingerprints with [SECURITY.md](../../../../SECURITY.md#signing-key). The first download rests on HTTPS.

## Malicious change to the workflows or scripts

- **Mitigation.** Pull requests run with read-only tokens and no secrets; no `pull_request_target`; zizmor, CodeQL and jactionlint audit the workflows; signing runs only on `main`, in `update.yaml`. Four rulesets ([rulesets](../ci-cd/rulesets.md)):
  1. *Main* (`main`): signed commits, clean code scanning (CodeQL, zizmor), a pull request (squash merge only, no approval needed: a solo repository) and 19 required status checks. Only the deploy key can bypass it; the Admin role cannot.
  2. *Protection, other branches*: signed commits and clean code scanning.
  3. *Protection* (every branch but `refs/heads/dependabot/**/*`): no deletion, force push or branch creation.
  4. *Tag Protection* (every tag): no deletion, force push or update; signed commits; no `creation` rule.

  The Admin role (the maintainer) can bypass rulesets 2 to 4. `GITHUB_TOKEN` can bypass none, so no workflow pushes a commit with it; it pushes only `update.yaml`'s signed release tags, on commits already on `main`.
- **Left over.** The maintainer's account is the final control: keep two-factor authentication on. The deploy key is a second way to push to `main` ([above](#leaked-keep-alive-deploy-key)).

## Malicious or hijacked action

- **Mitigation.** Every action is pinned to a commit SHA; Dependabot proposes updates; harden-runner records egress; zizmor flags impostor commits and unpinned actions.
- **Left over.** The maintainer's review of each update.

## Domain or Pages takeover

- **Mitigation.** HTTPS is enforced and the `CNAME` record points only to GitHub ([custom domain](../release/setup.md#custom-domain)).
- **Left over.** Until the domain is verified in the GitHub account, a dangling record is exploitable.

## Lost recovery-key backup

- **Mitigation.** [`key-review.yaml`](../../../../.github/workflows/key-review.yaml) opens an issue every January to check the offline backups and revocation certificates and review the rotation plan.
- **Left over.** The check itself is the maintainer's.

## Other threats

- **Leaked secret in the history.** Gitleaks scans the whole history on every pull request, every push to `main` and weekly; GitHub secret scanning and push protection are on.
- **Vulnerable dependency.** Dependabot and Dependency Review ([supply chain](supply-chain.md#actions-and-dependencies)). The packages' contents are Microsoft's.
- **Abuse of the name.** The packages and the site say they are unofficial and unaffiliated; the trademark is acknowledged ([compliance posture](../../legal/compliance-posture.md)).
