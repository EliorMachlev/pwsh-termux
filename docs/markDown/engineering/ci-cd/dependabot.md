# CI / CD: Dependabot and pinned tools

Part of the [CI / CD](../ci-cd.md) docs.

## What Dependabot updates

[`dependabot.yml`](../../../../.github/dependabot.yml) runs weekly (Mondays), with a 7-day cooldown after each upstream release. Six grouped pull requests:

1. the pinned GitHub Actions, moving both the SHA and its `# vX.Y.Z` comment (every `uses:` is a full SHA, except the local reusable workflow, called as `$/.github/workflows/build-packages.yaml`);
2. the hash-pinned Python requirements of `tools/zizmor` and `tools/docs-checks` (typos, PyYAML);
3. Hypothesis and its dependencies in [`tools/fuzz/`](../../../../tools/fuzz), hash-pinned;
4. the website's checkers in [`tools/site-lint/`](../../../../tools/site-lint) (npm: `vnu-jar`, `stylelint`, `stylelint-config-standard`; exact versions in `package.json`, integrity hashes in `package-lock.json`);
5. coverage.py in [`tools/coverage/`](../../../../tools/coverage), hash-pinned, for the `coverage` job;
6. the base image of [`.clusterfuzzlite/`](../../../../.clusterfuzzlite) (`docker`), pinned by digest.

These folders live under `tools/`, not `.github/`: Dependabot could not open pull requests for files under `.github/` (its API refused the change as "invalid or unauthorized"), while the same files at the top level were accepted.

These are the only ecosystems in the repository. The npm packages are CI tooling: `site.yaml` installs them with `npm ci --ignore-scripts` and checks them with `npm audit signatures`; no JavaScript ships on the site.

Dependabot's pull requests are held to the same [required checks](rulesets.md#required-status-checks) as any other; Dependency Review and zizmor check them too.

## Repository settings it needs

Two things outside the repository's files go with `dependabot.yml`:

1. **The `dependencies` label.** Every entry sets `labels: ["dependencies"]`. Dependabot does not create a missing label; the pull request then opens without it. Check with `gh label list`; create with `gh label create dependencies --description "Dependency updates"`.
2. **The ruleset exclusion.** *Protection* excludes `refs/heads/dependabot/**/*`; without it, its `creation` rule refuses Dependabot's branches and no pull request opens ([rulesets](rulesets.md#the-four-rulesets)).

## Pinned by hand

Dependabot does not follow a download, and nothing reminds you when these fall behind. Each is pinned by version and SHA-256:

1. the SBOM generators, at the top of `make-sboms.sh`;
2. jactionlint and shfmt, in `ci.yaml` (`JACTIONLINT_*`, `SHFMT_*`);
3. lychee, in `docs-checks.yaml` (`LYCHEE_*`).

[`tools/pinned-tools/bump.py`](../../../../tools/pinned-tools/bump.py) does Dependabot's job for them: it picks the newest stable release at least two weeks old (its GitHub publication time; for tools-java, the Last-Modified of that version's pom on Maven Central), takes the SHA-256 from the project's checksums file, else from the digest GitHub records for the asset (tools-java, which has neither, is hashed from the download), and prints the change; `--apply` rewrites the constants. A tool that fails is reported and skipped, the rest are still updated, and the exit status is 1.

1. Run `python3 tools/pinned-tools/bump.py`, then again with `--apply`.
2. Read the release notes. jactionlint's `pedantic` profile runs every rule and any finding fails, so a new rule can fail CI.
3. Run the offline tests ([build](../build.md)), commit and open a pull request. CI checks the new pins.
