# CI / CD: the audit of main

Part of the [CI / CD](../ci-cd.md) docs.

[`audit-main.yaml`](../../../../.github/workflows/audit-main.yaml) runs [`audit-main-commits.sh`](../../../../scripts/audit-main-commits.sh) on each push to `main`, daily and by hand.

## What it checks

Newest first, every commit after a baseline (`AUDIT_BASELINE_COMMIT`, the last commit made before the ruleset required signatures) that was committed in the last 90 days (`AUDIT_WINDOW_DAYS`); the newest 50 (`AUDIT_MIN_COMMITS`) whatever their dates, so a back-dated commit is still seen; and on a push, the pushed range.

A commit is fine if one of these holds:

1. GitHub reports its signature verified and its committer's account is the repository's owner (commits pushed before *Main* required pull requests; the ruleset now refuses such a push).
2. GitHub reports its signature verified, its committer's account is `web-flow`, **and** it is the merge commit of a merged pull request into `main`: `GET /repos/{owner}/{repo}/commits/{sha}/pulls` lists a pull request with `merged_at` set, base `main` and `merge_commit_sha` equal to the commit (hence `pull-requests: read`). `web-flow` also signs commits made in github.com's editor and the earlier commits of a rebase merge, which are findings. So merge with *Squash and merge* or a merge commit: a rebase merge of several commits flags all but its last, as would any `web-flow`-signed commit a merge commit brings in.
3. It is unsigned, passes the keep-alive [guard](keepalive.md#keep-alive-commit), and carries the status `keepalive/pushed` with state `success` created by `github-actions[bot]` (login and account id 41898282). Only a workflow's `GITHUB_TOKEN` creates statuses as that account, and a deploy key cannot create one, so a keep-alive-shaped commit pushed by hand with a leaked key is flagged.

A push that does not contain the previous tip (a rewritten `main`) is also a finding.

## Issues it opens

- **Findings:** one issue, *Unexpected unsigned commit on main*, found by exact title, with a table of the commits, their authors and the reasons. When the findings change, its body is replaced (with a comment); it is left alone when they do not, and closed with a comment on the next clean run. The job fails while there are findings. After dealing with one ([troubleshooting](troubleshooting.md#audit-and-keep-alive)), move `AUDIT_BASELINE_COMMIT` to the newest reviewed commit in a pull request, or the old commit stays flagged until it leaves the window.
- **A failed audit:** if the audit job itself fails (an API error, a baseline missing from the clone, a rewritten `main`), it has checked nothing. The `failed` job opens *The audit of main failed*, or comments on it if open; the next audit that finishes closes it.

Permissions: the audit job is read-only (`contents: read`, `pull-requests: read`, `statuses: read`); only the `report` and `failed` jobs have `issues: write`.

## What it is and is not

It is **detection**: tamper evidence after the fact, within a day (a push with a skip-CI token skips the push-triggered run, so the daily run is the bound).

It is not **prevention**: whoever can push to `main` can change this script and its workflow in the same push, and a verified signature only proves that the key belongs to the committer's account. Prevention is:

1. the main-only environment that holds the deploy key;
2. the [rulesets](rulesets.md) that keep deletion, force pushes and branch creation away from it;
3. workflow changes reaching `main` only through pull requests whose required checks pass (*Main*, which the maintainer's admin role cannot bypass);
4. a single deploy key.
