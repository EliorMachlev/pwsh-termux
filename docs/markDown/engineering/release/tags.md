# Release: signed release tags

Part of the [release](../release.md) docs.

Each `pwsh` and `pwsh-preview` release since this was added sits on an **annotated tag signed with the online signing key** (the key in `keys/` that signs the apt index). `git tag -v <tag>` then shows which commit built the release and that this repository's pipeline signed it, as OpenSSF's `version_tags_signed` criterion asks.

## How

[`release-tags.sh`](../../../../scripts/release-tags.sh) runs in `update.yaml`'s `publish` job:

1. **`sign`**, in the step that holds the key, after `build-repo.sh` has signed the index. For each `pwsh` and `pwsh-preview` `.deb` whose tag `<package>-<version>` (`~` written as `-`) the clone lacks (the checkout fetches every tag), it writes the tag object with `git mktag`: the commit being published (`GITHUB_SHA`), tagger `github-actions[bot]`, title `<package> <version>`, a message naming the key, and an armored detached signature by the online key, exactly as `git tag -s` would. It checks the result as `verify` does, then creates `refs/tags/<tag>`. A failure stops the run: nothing is published.
2. **`push`**, in the release step, which no longer holds the key. It verifies the tag again and pushes it with the job's `GITHUB_TOKEN` (`contents: write`; git gets the token from `gh auth git-credential` for that command only), unless the remote already has it (then it must be the same tag object). `gh release create --verify-tag` makes the release on it, so `gh` never creates a lightweight tag.
3. **`verify`**: the tag is annotated, names itself, points at a commit and carries exactly one signature, which verifies with `gpgv` against `keys/` alone and was made by an online key (during a rotation, either one), never the recovery key.

Tests: `scripts/test-release-tags.sh`, in CI's *Key rules and key tests* job ([tests](../ci-cd/tests.md#keys-and-release-tags)).

## Why `GITHUB_TOKEN` can push it

*Tag Protection* has no `creation` rule, and its `required_signatures` rule checks the commits a push brings, not the tag object ([GitHub community discussion](https://github.com/orgs/community/discussions/154293)). A release tag points at a commit already on `main`, signed, so the push brings none. Moving or deleting a tag stays refused for everyone without the Admin bypass ([rulesets](../ci-cd/rulesets.md)).

One limit: a `GITHUB_TOKEN` never holds the `workflows` permission, and GitHub refuses a new ref it creates on a commit whose `.github/workflows` differs from the default branch's ([discussion](https://github.com/orgs/community/discussions/151442)). That happens only if a pull request changing a workflow merges while a run is in progress. `push` then compares the tagged commit's `.github/workflows` with the remote `main`'s, pushes nothing and exits 3; the release step logs a warning and skips that release. The next run (a merge to `main` starts one) tags its own commit and releases it.

## Why GitHub shows them as unverified

The signing key is on no GitHub account, on purpose: there, GitHub would show commits it signs as the maintainer's, *Verified*, which the [audit of `main`](../ci-cd/audit.md) trusts, so a leak of the unattended key would reach further. The check is `git tag -v` with the published key ([SECURITY.md](../../../../SECURITY.md#verifying-a-release-tag)).

After a [rotation](signing-keys.md#rotating-the-signing-key), an older tag verifies with the key that signed it, which is in the keyring file at the tag's own commit (`git show <tag>:keys/pwsh-termux-archive-keyring.gpg`): the publish job signs only with an online key of that file.

## Older tags

`pwsh-7.7.0-1`, made earlier by `gh release create`, is a lightweight tag with no signature. It stays as it is: *Tag Protection* forbids moving it and its release is immutable.
