# CI / CD: keep-alive

Part of the [CI / CD](../ci-cd.md) docs.

In a public repository GitHub disables every scheduled workflow after 60 days without repository activity. For most schedules here that only delays a scan, but `update.yaml` must re-sign the index at least every 14 days (`Valid-Until`), so a disabled schedule becomes an *expired* error on every device two weeks later. Two mechanisms work against it:

1. the [API renewal](#schedule-keep-alive), which makes no commit;
2. a [keep-alive commit](#keep-alive-commit) on `main` after 30 quiet days, the documented kind of activity, because GitHub does not document that the renewal counts.

## Schedule keep-alive

[`keep-schedules-alive.sh refresh`](../../../../scripts/keep-schedules-alive.sh) finds every file in `.github/workflows` with a `schedule:` trigger, reads its state from the REST API, and calls `PUT /repos/{owner}/{repo}/actions/workflows/{file}/enable` on each one that is:

- `active`: renewing it before GitHub would disable it;
- `disabled_inactivity`: bringing it back; the run then fails, so the maintainer hears of it.

A `disabled_manually` workflow is left off: the [key recovery](../release/signing-keys.md#recovery-with-the-offline-key) turns `update.yaml` off on purpose.

It runs in three places, each a small job with only `actions: write` (and `contents: read` for the checkout), no secret and no other step:

1. `update.yaml`, job `keepalive`: daily at 04:23 UTC and on each push that deploys; independent of the build, so it runs when the build fails.
2. `staleness.yaml`, job `keepalive`: daily at 07:41 UTC, after the `check` job has recorded the states (whether that job passed or not).
3. `keepalive.yaml`, job `refresh`: Sundays and Wednesdays at 02:29 UTC; nothing else in it can fail.

Each run renews all scheduled workflows, the other two legs and itself included, so a broken or deleted leg does not stop the others. `staleness.yaml`'s `check` job (`actions: read`) opens the issue *A scheduled workflow is disabled* if it finds `disabled_inactivity`, before its own keep-alive job enables it again.

Dry run: `GH_REPO=EliorMachlev/pwsh-termux bash scripts/keep-schedules-alive.sh refresh --dry-run` (or `check`), with a token that can read Actions, such as `gh auth`'s.

**Why this design.** It needs no new long-lived secret (a personal token or App key) and adds no commits. A disabled workflow cannot enable anything, so three legs renew each other daily, *before* the limit.

**Verified and assumed** (checked on 2026-11-12):

- *Documented:* scheduled workflows in a public repository are disabled "when no repository activity has occurred in 60 days" ([events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule); [disabling and enabling a workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows)). A workflow's `state` is one of `active`, `deleted`, `disabled_fork`, `disabled_inactivity`, `disabled_manually`; the enable endpoint sets it to `active` ([REST: workflows](https://docs.github.com/en/rest/actions/workflows)). Enable needs the *Actions* permission with write access ([permissions for GitHub Apps](https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps)), which `permissions:` grants to `GITHUB_TOKEN` ([GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)). A commit that changes the `cron` of a deactivated scheduled workflow reactivates it.
- *Tested here:* with `actions: write`, enabling an active workflow returns `204 No Content`; with `actions: read`, `403`, though the state can be read. `test-keepalive.sh` tests the script's logic offline.
- *Assumed, not documented:* that enabling an active workflow restarts the 60-day count, as community keep-alive actions rely on (for example [`liskin/gh-workflow-keepalive`](https://github.com/liskin/gh-workflow-keepalive)). It cannot be tested short of 60 quiet days.

**If the assumption is wrong**, the keep-alive commit still lands between day 30 and 37 of a quiet spell. If that fails too, all schedules can stop on day 60 and nothing inside the repository can restart them. Then:

1. `staleness.yaml` prints the age of the last commit on `main` every day, and warns from day 45.
2. Any merged pull request (Dependabot opens grouped ones weekly) is a commit on `main` and resets the count.
3. The maintainer re-enables the workflows (Actions tab or `gh workflow enable`) and runs `update.yaml` by hand. The index gives 14 more days before users see an error.

## Keep-alive commit

GitHub documents only commits on the default branch as repository activity. [`keepalive-commit.yaml`](../../../../.github/workflows/keepalive-commit.yaml) runs [`keepalive-commit.sh`](../../../../scripts/keepalive-commit.sh) every Monday. If `main`'s newest commit is younger than 30 days (`KEEPALIVE_MIN_AGE_DAYS`), it does nothing; otherwise it pushes one commit. So at most one such commit a month, and none while pull requests are being merged.

**`keep.alive`**, at the repository root, is written only by this workflow. It holds one line, the UTC time of the last keep-alive commit (`2026-11-12T16:00:00Z`, exactly `KEEPALIVE_TIMESTAMP_REGEX` in [`common.sh`](../../../../scripts/lib/common.sh), 21 bytes with the newline). Nothing reads it; do not edit it by hand.

**The commit** is built with git plumbing in a temporary repository, on `main`'s tip fetched at depth 1: the tip's tree with `keep.alive` set; author and committer `github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>`; message `chore(keepalive): refresh keep.alive [skip ci]`, so no push-triggered workflow runs for it. It is unsigned: the deploy key that pushes it bypasses `main`'s ruleset.

**Scorecard's SAST check ignores it:** that check (Scorecard v5.6.0) skips commits of `main` with no merged pull request, so a keep-alive commit counts neither for nor against.

**The guard**, before every push (the audit applies the same rules, `keepalive_commit_problems` in `common.sh`):

1. exactly one parent, the tip just fetched;
2. exactly one changed path, `keep.alive`, added or modified, a regular file (mode `100644`, not a link). The raw NUL-separated list (`git diff -z --name-only`) must equal `keep.alive` plus one NUL byte for byte (`is_keepalive_path_list`), so a file named `keep.alive<newline>` or `<newline>` cannot slip through. It is also checked on the diff from the fetched tip itself;
3. content: one timestamp line that is also a real date;
4. author and committer exactly the bot identity, and the message exactly as above.

Anything else, and nothing is pushed.

**The push** is `git push <remote> <commit>:refs/heads/main` over SSH to `git@github.com`, with GitHub's Ed25519 host key pinned in the script. If the push is refused and `main` has moved, the script fetches again and starts over (the new tip may be young, which ends the run), at most 3 times; if `main` has not moved, it fails at once: that is a rule, not a race. Then it posts the commit status `keepalive/pushed` (`success`) with the job's `GITHUB_TOKEN` (`statuses: write`), which the audit requires. If that call fails, the job fails and the next audit flags the commit.

## The keep-alive deploy key

**Setup (in place):** a read-write deploy key, *pwsh-termux keepalive (push to main)*, and the environment `keepalive` (deployment branch policy: `main` only) holding its private half as the secret `KEEPALIVE_DEPLOY_KEY`. The private half exists nowhere else; rotation makes a new key, so nobody needs a copy.

**How it is used.** A run from any other branch, a pull request or a fork cannot read the secret. The job refuses any ref but `refs/heads/main` before the checkout, and the script checks again. The script pipes the key into an `ssh-agent` (`ssh-add -`, a 15-minute lifetime), removes it from its environment, and kills the agent on exit: never on disk, never echoed, and the checkout keeps `persist-credentials: false`. (`actions/checkout`'s `ssh-key` input would write it to a file and leave it configured, which zizmor's `artipacked` audit warns about.) Nothing else in the job runs code: harden-runner, a shell check of the ref, the pinned checkout, the script.

**Why a deploy key.** `main` requires signed commits, clean code scanning, a pull request and passing checks ([rulesets](rulesets.md)). In a personal repository `GITHUB_TOKEN` cannot be a bypass actor, and signing a workflow's commit so GitHub verifies it needs a user's or a GitHub App's key, a broader credential. A deploy key can be a bypass actor (`actor_type: DeployKey`), reaches this repository only, and does nothing but Git over SSH: no API, issues, settings or secrets.

**What a leaked key could do:** push any fast-forward commit to `main` past every rule of *Main*, including a workflow change, which then runs with whatever that workflow asks for, secrets included. Hence the [rulesets](rulesets.md) keep deletion, force push and creation where the key has no bypass, and every commit on `main` is [audited](audit.md). It cannot delete or rewrite `main` or create branches (except under `dependabot/`); other branches hold it to signed commits; it could create a tag on an existing signed commit, but not move or delete one.

**One deploy key only.** The `DeployKey` bypass has no key id (`actor_id: null`): it covers *every* deploy key. Never add a second one, read-only or not, even for a moment. `gh api repos/EliorMachlev/pwsh-termux/keys` must list exactly one.

### Rotating the keep-alive deploy key

At once if the audit issue is open and the commits are not yours, or if the secret may have been exposed; otherwise when convenient (the yearly key review is a good moment). The bypass covers whichever deploy key exists, so the ruleset does not change. Delete the old key **before** adding the new one.

```bash
R=repos/EliorMachlev/pwsh-termux
ssh-keygen -t ed25519 -N '' -C "pwsh-termux keepalive" -f keepalive_key        # on a trusted machine
gh api $R/keys --jq '.[] | {id, title}'                                          # the old key's id
gh api -X DELETE $R/keys/<old-id>                                                # first: the old key stops working now
gh api -X POST $R/keys -f title="pwsh-termux keepalive (push to main)" -f key="$(cat keepalive_key.pub)" -F read_only=false
gh secret set KEEPALIVE_DEPLOY_KEY --env keepalive < keepalive_key
shred -u keepalive_key keepalive_key.pub                                         # no copy is kept
gh api $R/keys --jq length                                                       # 1
```

Then run *Keep-alive commit* with *ignore_age* once ([checking the rulesets](rulesets.md#checking-them), step 3).
