# Exceptions

The only suppressed or ignored findings in the repository, and why. **There are none.**

Every scanner runs without a baseline, an allowlist or an ignore file:

- `shellcheck` runs at `--severity=style` with no `# shellcheck disable=` comments;
- zizmor, CodeQL, jactionlint and Gitleaks have no ignore entries (jactionlint runs its `pedantic` profile with `--strict-exit --no-ignores --config-file=/dev/null`, so every rule runs, a finding of any level fails, and no ignore comment, config file or baseline can hide or downgrade one);
- lychee has no `.lycheeignore`, and `_typos.toml` has no extended words;
- no rule is disabled in any configuration.

## Adding one

Adding an exception is the maintainer's decision, never a contributor's or an assistant's. If you think one is warranted, open an issue saying what the finding is, where, and why it has no real fix. If it is accepted, it is recorded here, one numbered entry each, with the finding, the file, the reason and what would let it be removed, in the same commit that adds the suppression.

A suppression that is not listed here is a bug.
