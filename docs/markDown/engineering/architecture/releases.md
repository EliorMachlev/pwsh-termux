# Choosing releases

[`scripts/find-releases.sh`](../../../../scripts/find-releases.sh) decides what to package. It prints at most two lines:

```text
stable v7.7.0
preview v7.8.0-preview.1      # only when newer than stable
```

## How

It reads the 50 most recent releases from the GitHub API for `PowerShell/PowerShell` (authenticated when `GITHUB_TOKEN` is set, to avoid the anonymous rate limit) and keeps, with `jq`, releases that:

1. are not drafts;
2. have the wanted `prerelease` flag (false for stable, true for preview);
3. have a `powershell-<version>-linux-arm64.tar.gz` asset.

The highest tag by `sort -V` wins. Version, not date: Microsoft ships patch releases for older lines after newer ones (a `v7.4.x` after `v7.7.0`).

## The preview rule

A preview is printed only if its core version (the tag without `v` and anything after the first `-`) is strictly greater than stable's: once `v7.7.0` is out, `v7.7.0-rc.1` is no longer a preview. Without a qualifying preview, `pwsh-preview` is not built, so it drops out of the index until the next one; an installed copy stays as it is.

## Failure behavior

1. No stable release: exit 1, the run fails, nothing is deployed.
2. A release whose arm64 tarball is not uploaded yet is skipped; the next daily run picks it up.
3. The script downloads nothing; [`build-deb.sh`](packaging.md) validates the tag before putting it in a URL.

## Tests

[`test-find-releases.sh`](../../../../scripts/test-find-releases.sh) runs offline against stub responses. The `package` job in [`ci.yaml`](../../../../.github/workflows/ci.yaml) also runs the real script on every change, so a change in Microsoft's release naming fails a check.
