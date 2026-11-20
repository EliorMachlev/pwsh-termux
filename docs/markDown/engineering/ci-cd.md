# CI / CD

Workflows are in [`.github/workflows/`](../../../.github/workflows).

## Topics

1. [Workflows](ci-cd/workflows.md): what each one does and when it runs.
2. [What the tests cover](ci-cd/tests.md): CI's test jobs, coverage, fuzzing, DCO.
3. [Rulesets and required checks](ci-cd/rulesets.md): the 23 required checks and how `main` is protected.
4. [Keep-alive](ci-cd/keepalive.md): the schedule renewal, the keep-alive commit and its deploy key.
5. [The audit of main](ci-cd/audit.md)
6. [Dependabot and pinned tools](ci-cd/dependabot.md)
7. [When a run fails](ci-cd/troubleshooting.md)

## Rules every workflow follows

- **Every action pinned to a commit SHA**, its version in a trailing comment (`uses: actions/checkout@<sha> # v7.0.1`). Tags can be moved; SHAs cannot. Dependabot updates both.
- **Least privilege.** `permissions: contents: read` at the top; a job asks for more only where needed, with a comment saying why:
  - `security-events: write` for code scanning;
  - `pages: write` and `id-token: write` to deploy;
  - `contents: write` to push the signed release tags and create the releases;
  - `issues: write` for the staleness, key-review, audit and security.txt-renewal issues;
  - `actions: write` only on the small keep-alive jobs;
  - `statuses: write` only on the job that pushes the [keep-alive commit](ci-cd/keepalive.md#keep-alive-commit).
- **`step-security/harden-runner` first in every job**, in `block` mode with an `allowed-endpoints` list of the hosts that job needs (GitHub; the package index for a job that installs; the apt mirrors for one that runs `apt-get`; the artifact storage for one that moves artifacts). Two jobs stay in `audit` (it records the runner's network use): `Scorecard analysis` (its hosts change with the checks Scorecard adds, and it runs only on `main`) and `Links (lychee)` (the weekly online run reaches whatever the docs link to). The lists were taken from the audit logs of recent successful runs; a job that runs only on `main` or on a schedule first runs there. The two jobs that hold secrets, `sign` in `update.yaml` (`signing` environment; it may reach only `github.com` and GitHub's Actions service) and the keep-alive commit job in `keepalive-commit.yaml` (`keepalive` environment), use `egress-policy: block` with an `allowed-endpoints` list limited to GitHub. `publish` (the write token, no key) is in `block` mode too. The artifact storage wildcard (`*.blob.core.windows.net`) is allowed only where a job moves artifacts: `verify` and `assemble` and `publish` in `update.yaml` (artifact download, Pages upload), the Pages upload in `recover.yaml`'s `verify`, and the build and test jobs that upload artifacts. Never `sign`, `deploy` or the keep-alive jobs. `deploy` (Pages) is in `block` mode with the GitHub-only list: it contacted only `api.github.com` and `*.actions.githubusercontent.com` in the audit run. If a job fails on a blocked connection, first find out why that host is contacted. For an ordinary job, add the endpoint named in the run's log to that job's `allowed-endpoints`, and nowhere else. For `sign` and the keep-alive commit job (the jobs that hold secrets), never add a host just because the log names it: an unexpected host there is a possible exfiltration attempt, so investigate the step and the action version that contacted it, and widen the list only after a review of the change that caused it.
- **`persist-credentials: false`** on every checkout. The keep-alive commit pushes with a deploy key held in an `ssh-agent` for one script; `update.yaml`'s `publish` job pushes release tags with its token, which git gets from `gh auth git-credential` for that one command (never an argument, a file or `.git/config`).
- **Concurrency.** A newer push to a pull request or topic branch cancels a run still going; runs on `main` always finish. Deploys share a `pages` group and are never cancelled.
- **Timeouts** on every job.
- **`defaults: run: shell: bash`** wherever there is a `run:` step, so each script runs with `pipefail` (GitHub's implicit `bash -e {0}` hides a failure on the left of a `|`). Under `pipefail` a reader that stops early (`grep -q`, `head`, `awk '{…; exit}'`) makes the writer fail with SIGPIPE, so scripts use `jq`'s `first(…)`, a here-string, or an `awk` that reads to the end.
- **Fixed runner images** (`ubuntu-24.04` or `ubuntu-26.04`, never `ubuntu-latest`): moving to a new image is a change in this repository, and can bring new tool versions such as a stricter ShellCheck.
- **A `name:` on every job, every `if:` written as `${{ … }}`.** jactionlint's pedantic profile checks these, the pinning, the runner images and the permission comments.
- **No `pull_request_target`**, and untrusted event data is never interpolated into a script.

## Secrets

1. **`GPG_PRIVATE_KEY`** and **`GPG_PASSPHRASE`**: the signing key and its passphrase. Secrets of the environment `signing` (main only), never repository secrets, read only by `update.yaml`'s "Sign the index and the tag payloads" step in the `sign` job ([how](release/setup.md#the-signing-environment)).
2. **`KEEPALIVE_DEPLOY_KEY`**: a secret of the environment `keepalive` (main only), used only by `keepalive-commit.yaml`'s push step ([keep-alive deploy key](ci-cd/keepalive.md#the-keep-alive-deploy-key), [security](security.md#secrets)).

`GITHUB_TOKEN` is the workflows' own, scoped per job.
