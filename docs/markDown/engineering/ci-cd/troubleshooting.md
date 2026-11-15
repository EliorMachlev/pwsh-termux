# CI / CD: when a run fails

Part of the [CI / CD](../ci-cd.md) docs. Fix the cause; never skip a check.

If `build`, `verify` or `publish` in `update.yaml` fails, `deploy` does not run and the site stays as it was. The `keepalive` job runs independently, so a run can fail after `deploy` has published: check the `deploy` job, not only the run.

## Provenance and signing

- **The `verify` job fails:** the keyring package has no valid provenance from `build-packages.yaml` at this commit. Nothing is signed or published.
- **"GPG_PRIVATE_KEY secret is not set":** the secret is missing ([setup](../release/setup.md#the-signing-environment)).
- **"the signing key … is not the online key in …"** from `build-repo.sh`: the `GPG_PRIVATE_KEY` secret and `keys/` disagree (one changed without the other, or `keys/ROTATION` is missing or stale; [signing keys](../release/signing-keys.md#rotating-the-signing-key)).
- **"gpg could not sign …"** from `build-repo.sh` or `release-tags.sh`: the key is passphrase-protected and `GPG_PASSPHRASE` is missing or wrong, or the key itself is unusable.
- **Warning *GPG_PASSPHRASE secret is not set*:** printed before signing, when `GPG_PASSPHRASE` is missing from `signing`. If signing then fails with "gpg could not sign", the key is protected: restore `GPG_PASSPHRASE`. If signing succeeds, `GPG_PRIVATE_KEY` has no passphrase: add one and set both secrets again ([adding a passphrase](../release/setup.md#the-signing-environment)).
- **"Write the SBOMs" fails:** a tool's download or a validation failed; the log names the file ([pinned by hand](dependabot.md#pinned-by-hand)).

## Packages and index

- **Checksum mismatch or "no checksum for …":** Microsoft's `hashes.sha256` and the tarball disagree, or its format changed. Do not work around it ([packaging](../architecture/packaging.md)).
- **`find-releases.sh` finds no stable release:** usually the GitHub API is down or rate limited; re-run.
- **Issue *The live apt index is stale or unreachable*:** `staleness.yaml` found fewer than 7 days left, an index that does not verify against `keys/`, or no index. Check `update.yaml`'s recent runs first; the issue closes itself once the index is fresh.
- **`pkg update` says the Release file *is expired*:** `update.yaml` has not deployed for more than 14 days. Fix or re-run the failing run; the next deploy fixes every device. During a recovery, the maintainer re-signs offline instead ([recovery](../release/signing-keys.md#recovery-with-the-offline-key)).
- **"… is more than 14 days after Date", "expired at", "only N day(s) left"** from `build-repo.sh`, `recovery-sign.sh` or `verify-recovery-repo.sh`: the `Release` window is wrong or too old. For a recovery, run `build-repo.sh` again and sign in the same sitting.

## Audit and keep-alive

- **A scheduled workflow stops running**, or issue *A scheduled workflow is disabled*: GitHub disabled it after 60 days without activity and the [keep-alive](keepalive.md#schedule-keep-alive) did not hold, or a keep-alive run failed with *GitHub had disabled … for inactivity*.
  1. Re-enable each scheduled workflow in state `disabled_inactivity` (`gh workflow enable <file>`, or the Actions tab). Leave one in `disabled_manually` off: a [recovery](../release/signing-keys.md#recovery-with-the-offline-key) turns `update.yaml` off on purpose.
  2. If `update.yaml` was among them, run it by hand (the index expires 14 days after its last re-sign).
  3. If it keeps happening, merge something to `main`.
- ***could not enable … (does the job have actions: write?)*:** the job's `permissions:` lost `actions: write`.
- **Issue *The audit of main failed*:** the audit job failed, so nothing was checked. Read the linked run.
  - An API error: run *Audit main* again.
  - *the baseline … is not an ancestor of HEAD*: `main` was rewritten; treat it as a finding (next item).
  - *could not read the pull requests of …*: the job lost `pull-requests: read`, or the API failed.
- **Issue *Unexpected unsigned commit on main*:** a commit on `main` is neither signed by a trusted account nor a keep-alive commit with its status ([audit](audit.md)). Treat it as a possible leak of the keep-alive deploy key:
  1. [Rotate the key](keepalive.md#rotating-the-keep-alive-deploy-key).
  2. Look at what the commits changed and revert what is not yours.
  3. Check recent workflow runs, and rotate any secret a changed workflow could have read.

  The harmless case: a keep-alive commit flagged only for its missing status, after a keep-alive run that failed while posting it; that run's log says so.
- **`keepalive-commit.yaml` fails:**
  - *the push was refused and main has not moved*: the ruleset does not let the deploy key push to `main` (not set up, or the bypass removed), or the key was rotated without updating the secret.
  - *ssh-add refused KEEPALIVE_DEPLOY_KEY*: the secret is not an OpenSSH private key.
  - *KEEPALIVE_DEPLOY_KEY is not set*: the job did not run in the `keepalive` environment, or the secret is missing.
