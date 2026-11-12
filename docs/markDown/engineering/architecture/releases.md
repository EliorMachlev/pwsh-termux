# Choosing releases

[`scripts/find-releases.sh`](../../../../scripts/find-releases.sh) decides what to package. It prints at most two lines:

```text
stable v7.7.0
preview v7.8.0-preview.1      # only when newer than stable
```

## How

It reads the 50 most recent releases from `https://api.github.com/repos/PowerShell/PowerShell/releases` (with `GITHUB_TOKEN` if set, which avoids the unauthenticated rate limit on CI) and, with `jq`, keeps releases that

- are not drafts,
- have the wanted `prerelease` flag (false for stable, true for preview), and
- have an asset named `powershell-<version>-linux-arm64.tar.gz`.

The highest tag by `sort -V` wins. **Version, not date:** Microsoft publishes patch releases for older lines after newer ones (a `v7.4.x` can appear after `v7.7.0`), so the newest release is not necessarily the highest.

## The preview rule

A preview is published only if its *core* version (the tag without `v` and without anything after the first `-`) is strictly greater than stable's. `v7.7.0-rc.1` is older than `v7.7.0`, so once `7.7.0` is out it is not a preview any more. When no preview qualifies, `pwsh-preview` simply stays at its last published version until one does; it is not removed.

## Failure behavior

- No stable release found: exit 1, the run fails and nothing is deployed.
- A release whose tarball is not uploaded yet is skipped, so the next daily run picks it up.
- The script only chooses tags; it downloads nothing. [`build-deb.sh`](packaging.md) validates the tag format (`vMAJOR.MINOR.PATCH` with an optional `-suffix`) before using it in a URL.

## Tests

`scripts/find-releases.sh` is run for real by the `package` job in [`ci.yaml`](../../../../.github/workflows/ci.yaml) on every change, so a change to Microsoft's release naming shows up as a failed check.
