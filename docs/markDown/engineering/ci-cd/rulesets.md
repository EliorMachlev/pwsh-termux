# CI / CD: rulesets and required checks

Part of the [CI / CD](../ci-cd.md) docs.

**Status:** *Main* as described here (no Admin bypass, a `pull_request` rule, the required status checks below) has been applied since 2026-11-14 with [the command below](#applying-main). No ruleset has a `required_deployments` rule.

## The four rulesets

A bypass actor bypasses *every* rule of its ruleset, and rulesets stack: a push must pass every ruleset for its ref, each bypassed only by its own actors. So the keep-alive deploy key bypasses only a ruleset for `main` alone, and deletion, force push and creation sit in a ruleset it cannot bypass. The Admin role is `RepositoryRole` 5.

1. ***Main*** (id `27198868`), on `refs/heads/main`.
   - Rules: `required_signatures`; `code_scanning` (CodeQL, zizmor); `pull_request` (no approval needed, squash merge only, stale approvals dismissed); `required_status_checks` (strict: the branch must be up to date; the [19 checks below](#required-status-checks)).
   - Bypass: **`DeployKey`** only (`actor_id: null`, `bypass_mode: always`). **Not** the Admin role.
2. ***Protection, other branches*** (id `27198871`), on all branches except `refs/heads/main`.
   - Rules: `required_signatures`; `code_scanning` (CodeQL, Scorecard, zizmor).
   - Bypass: Admin role only.
3. ***Protection*** (id `27110284`), on all branches (`~ALL`) except Dependabot's (`refs/heads/dependabot/**/*`).
   - Rules: `deletion`, `non_fast_forward`, `creation`.
   - Bypass: Admin role only. **Not** the deploy key.
4. ***Tag Protection*** (id `27110388`), on all tags (`~ALL`).
   - Rules: `deletion`, `non_fast_forward`, `update`, `required_signatures`, and a `required_status_checks` rule that lists no check. No `creation` rule: `update.yaml` creates [release tags](../release/tags.md) with `GITHUB_TOKEN`, which cannot bypass a ruleset.
   - Bypass: Admin role only.

**What *Main* means in practice.** Every change reaches `main` through a pull request whose 19 required checks passed on its head commit, merged with *Squash and merge*. GitHub makes that commit as `web-flow` and signs it, so it is *Verified*, passes `required_signatures`, and the [audit](audit.md) accepts it as a merged pull request's merge commit. The maintainer cannot push to `main` directly, nor merge a pull request whose checks have not passed (a check that fails for an outside reason, such as a download in *Package build*, is re-run). The only bypass is the keep-alive deploy key. As an admin, the maintainer can still edit the ruleset itself: that is the way out if a rule must be lifted, and it shows in the ruleset's history.

***Protection, other branches*** holds other branches to signed commits; without it the deploy key could push unsigned commits to any existing branch, whose workflows then run. The Admin bypass on *Protection* is what lets the maintainer create branches.

**Dependabot's branches are excluded from *Protection*** (`"exclude": ["refs/heads/dependabot/**/*"]`):

- Why: Dependabot is not the Admin role, yet it creates, force-pushes and deletes its branches. Its branch names have several segments, which `refs/heads/dependabot/**` does not match and `refs/heads/dependabot/**/*` does.
- What still applies: *Protection, other branches* (signed commits) and *Main* for anything reaching `main`.
- What it gives up: anyone who can push (the maintainer, or a leaked deploy key) can create, force-push and delete a branch under `dependabot/`, pointing it at any existing commit. A push to an open Dependabot pull request's branch runs its workflows (read-only token, no secrets) and changes what it would merge: read a Dependabot pull request's diff, not only its title.
- The exclusion is part of the ruleset's body: the `PUT` under [re-creating them](#re-creating-them) sends it; a `PUT` without it blocks Dependabot again.

**Limits.**

- The `DeployKey` bypass has no key id: it covers *every* deploy key the repository has or will have, so there must only ever be one ([rotating it](keepalive.md#rotating-the-keep-alive-deploy-key)).
- `GITHUB_TOKEN` cannot be a bypass actor in a personal repository, so no workflow can push a commit with it to any branch, nor create a branch for a pull request outside `dependabot/` (no workflow uses that namespace, and a pull request opened with `GITHUB_TOKEN` starts no workflow, so its required checks would never report). Hence the keep-alive commit uses the deploy key, and [`renew-security-txt.yaml`](../../../../.github/workflows/renew-security-txt.yaml) opens an issue instead ([website](../website.md#updating-securitytxt)).

## Required status checks

A required check must report on **every** pull request into `main`, or that pull request can never merge: when a workflow is skipped by branch filtering, path filtering or a commit message, its "checks associated with that workflow will remain in a "Pending" state" and the pull request is "blocked from merging" ([workflow syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#onpushpull_requestpull_request_targetpathspaths-ignore)). So these workflows have no `paths` filter on `pull_request` (their `push` filters on `main` stay), and a pull request's commit messages must not carry a skip-CI token.

Each check is the job's `name:`, from the GitHub Actions app (`integration_id` **15368**) unless noted. Pinning the app matters: GitHub Advanced Security (app 57789) also posts check runs named `zizmor` and `CodeQL` for the uploaded results.

1. `shellcheck`: [`ci.yaml`](../../../../.github/workflows/ci.yaml), job `shellcheck`
2. `jactionlint`: `ci.yaml`, job `jactionlint`
3. `Key rules and key tests`: `ci.yaml`, job `keys`
4. `Schedule keep-alive tests`: `ci.yaml`, job `keepalive`
5. `Keep-alive commit and audit tests`: `ci.yaml`, job `keepalive-commit`
6. `Packaging script tests`: `ci.yaml`, job `packaging-tests`
7. `Coverage`: `ci.yaml`, job `coverage`
8. `Package build`: `ci.yaml`, job `package`
9. `Links (lychee)`: [`docs-checks.yaml`](../../../../.github/workflows/docs-checks.yaml), job `links` (offline on pull requests)
10. `Spelling (typos)`: `docs-checks.yaml`, job `spelling`
11. `Check the website`: [`site.yaml`](../../../../.github/workflows/site.yaml), job `check`
12. `Validate the HTML and CSS`: `site.yaml`, job `validate`
13. `zizmor`: [`zizmor.yaml`](../../../../.github/workflows/zizmor.yaml), job `zizmor`
14. `CodeQL (actions)`: [`codeql.yaml`](../../../../.github/workflows/codeql.yaml), job `analyze`
15. `Dependency Review`: [`dependency-review.yaml`](../../../../.github/workflows/dependency-review.yaml), job `dependency-review`
16. `Gitleaks (whole history)`: [`gitleaks.yaml`](../../../../.github/workflows/gitleaks.yaml), job `gitleaks`
17. `Fuzz (Hypothesis)`: [`fuzz.yaml`](../../../../.github/workflows/fuzz.yaml), job `fuzz`
18. `CodeRabbit`: the CodeRabbit GitHub App (`integration_id` 347564), its review
19. `DCO`: [`dco.yaml`](../../../../.github/workflows/dco.yaml), job `dco`

**Why these names hold.** None of these jobs has a matrix or calls a reusable workflow (which would name the check `caller / callee` or add the matrix values), no two jobs that run on a pull request share a name, and none has a job-level `if:`.

**Not required, on purpose:**

- *Keep-alive commit (dry run)* and *Renew the scheduled workflows (dry run)* run only when their own files change (a `paths` filter), and their non-dry-run twins are skipped by `if:` on a pull request. A skipped job "will report its status as "Success". It will not prevent a pull request from merging, even if it is a required check." ([using conditions](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/using-conditions-to-control-job-execution)), so requiring one would check nothing.
- *Scorecard analysis* does not run on pull requests (the action supports `push` and `schedule`). For the same reason Scorecard is not in *Main*'s `code_scanning` rule, which would wait for its results forever. It still runs on each push to `main` and weekly, and *Protection, other branches* keeps all three tools.

**Cancelled runs.** A newer push to a pull request cancels the older run; the checks are read from the new head commit, so none gets stuck. A run cancelled by hand or by a time-out is re-run. With `strict_required_status_checks_policy: true`, merging one pull request leaves the others behind until each is updated with `main`.

**Dependabot** pull requests run the same workflows, with a read-only token unless a job asks for more, and no secrets; no required job needs a secret.

## Applying Main

A `PUT` replaces the whole ruleset; read it first with `gh api repos/EliorMachlev/pwsh-termux/rulesets/27198868`.

```bash
gh api -X PUT repos/EliorMachlev/pwsh-termux/rulesets/27198868 --input - <<'JSON'
{
  "name": "Main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "bypass_actors": [
    {"actor_type": "DeployKey", "actor_id": null, "bypass_mode": "always"}
  ],
  "rules": [
    {"type": "required_signatures"},
    {"type": "code_scanning", "parameters": {"code_scanning_tools": [
      {"tool": "CodeQL", "alerts_threshold": "all", "security_alerts_threshold": "all"},
      {"tool": "zizmor", "alerts_threshold": "all", "security_alerts_threshold": "all"}
    ]}},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "allowed_merge_methods": ["squash"]
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [
        {"context": "shellcheck", "integration_id": 15368},
        {"context": "jactionlint", "integration_id": 15368},
        {"context": "Key rules and key tests", "integration_id": 15368},
        {"context": "Schedule keep-alive tests", "integration_id": 15368},
        {"context": "Keep-alive commit and audit tests", "integration_id": 15368},
        {"context": "Packaging script tests", "integration_id": 15368},
        {"context": "Coverage", "integration_id": 15368},
        {"context": "Package build", "integration_id": 15368},
        {"context": "Links (lychee)", "integration_id": 15368},
        {"context": "Spelling (typos)", "integration_id": 15368},
        {"context": "Check the website", "integration_id": 15368},
        {"context": "Validate the HTML and CSS", "integration_id": 15368},
        {"context": "zizmor", "integration_id": 15368},
        {"context": "CodeQL (actions)", "integration_id": 15368},
        {"context": "Dependency Review", "integration_id": 15368},
        {"context": "Gitleaks (whole history)", "integration_id": 15368},
        {"context": "Fuzz (Hypothesis)", "integration_id": 15368},
        {"context": "CodeRabbit", "integration_id": 347564},
        {"context": "DCO", "integration_id": 15368}
      ]
    }}
  ]
}
JSON
```

**Renaming a job renames its check:** change the job's `name:` and the list above in one pull request. That pull request cannot report the old name, so the maintainer replaces the name in the ruleset just before merging it; other open pull requests then need `main` merged in to report the new one.

## Re-creating them

Only if they are lost, or for a new repository (the ids then change, and so must this page). Order matters, so `main` is never unprotected:

1. Create *Main*: the body above, sent with `-X POST $R/rulesets`.
2. Create *Protection, other branches*.
3. Reduce *Protection* to its three rules (a `PUT` on the existing ruleset; `POST $R/rulesets` if it is gone).

```bash
R=repos/EliorMachlev/pwsh-termux
ADMIN='{"actor_type":"RepositoryRole","actor_id":5,"bypass_mode":"always"}'

# 2. Signatures and code scanning on every other branch, with no deploy-key bypass.
gh api -X POST $R/rulesets --input - <<JSON
{"name":"Protection, other branches","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~ALL"],"exclude":["refs/heads/main"]}},
 "bypass_actors":[$ADMIN],
 "rules":[{"type":"required_signatures"},
  {"type":"code_scanning","parameters":{"code_scanning_tools":[
   {"tool":"CodeQL","alerts_threshold":"all","security_alerts_threshold":"all"},
   {"tool":"Scorecard","alerts_threshold":"all","security_alerts_threshold":"all"},
   {"tool":"zizmor","alerts_threshold":"all","security_alerts_threshold":"all"}]}}]}
JSON

# 3. Protection keeps only deletion, non-fast-forward and creation, on all branches
#    but Dependabot's (it must create, rebase and delete them).
gh api -X PUT $R/rulesets/27110284 --input - <<JSON
{"name":"Protection","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~ALL"],"exclude":["refs/heads/dependabot/**/*"]}},
 "bypass_actors":[$ADMIN],
 "rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"creation"}]}
JSON
```

## Checking them

1. **The rules on `main`:** `gh api $R/rules/branches/main --jq '[.[] | "\(.type) \(.ruleset_id)"]'` lists `deletion`, `non_fast_forward` and `creation` from *Protection*, and `required_signatures`, `code_scanning`, `pull_request` and `required_status_checks` from *Main*. On any other branch (`$R/rules/branches/<branch>`): `required_signatures` and `code_scanning` from *Protection, other branches*, plus *Protection*'s three rules except under `dependabot/`.
2. **The bypass lists:** `gh api $R/rulesets/<id> --jq .bypass_actors` for each. *Main* lists `DeployKey` and nothing else; the other three list the Admin role only. `gh api $R/keys --jq length` is `1`.
3. **A keep-alive push succeeds** (verified when the rulesets were set up). Run *Keep-alive commit* with *ignore_age* (`gh workflow run keepalive-commit.yaml -f ignore_age=true`): it pushes one commit that changes only `keep.alive` and posts `keepalive/pushed`; `main`'s history shows it unsigned, by `github-actions[bot]`. **Rule insights** (`gh api "$R/rulesets/rule-suites?ref=refs/heads/main" --jq '.[0] | {actor_name, result, after_sha}'`) shows that push with result `bypass`. Then run *Audit main* by hand: it must pass and leave no issue open.
4. **Anything else is refused.** The deploy key's private half is only in the environment, so this is read from the configuration rather than tried:
   - a force push or deletion of `main`, or a new branch outside `dependabot/`, falls under *Protection*, which the deploy key cannot bypass;
   - a push to another existing branch falls under *Protection, other branches* (unsigned is refused);
   - tags fall under *Tag Protection*: the deploy key could create a tag on an existing signed commit (not on an unsigned keep-alive commit), but not move or delete one. That would show as an unexpected tag or release, not on `main`.

   What the deploy key *can* push to `main` beyond `keep.alive` is limited by `keepalive-commit.sh`'s guard and by who can run it, not by GitHub: that residual risk is what the [audit](audit.md) is for. To watch the refusals happen, rebuild the three rulesets in a throwaway repository with its own deploy key; never add a second deploy key here.
5. **Normal work:** a pull request merges with *Squash and merge* once its 19 required checks have passed and code scanning is clean; a direct push to `main` by the maintainer is refused; the maintainer can still create branches.
