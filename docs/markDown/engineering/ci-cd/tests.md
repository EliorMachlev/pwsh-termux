# CI / CD: what the tests cover

Part of the [CI / CD](../ci-cd.md) docs. The jobs are in [`ci.yaml`](../../../../.github/workflows/ci.yaml) unless noted. The `scripts/test-*.sh` tests run offline, with throwaway keys and stubs (`gh`, `curl`, the SBOM tools) and no secret. Only the package build downloads a real release. To run them locally: [build](../build.md).

## Linters

1. **`shellcheck`** on `scripts/*.sh` and `scripts/lib/*.sh`.
2. **`jactionlint`** ([jdx's maintained fork of actionlint](https://github.com/jdx/jactionlint)) on every workflow and `dependabot.yml`. A release binary pinned by version and SHA-256, checked before it runs. It runs the `pedantic` profile with `--strict-exit`, `--no-ignores` and `--config-file=/dev/null`: a finding of any level, `info` included, fails the job, and nothing can be silenced. Its opt-in and online rules are not run. Unlike actionlint, it understands `uses: $/…`, which `update.yaml` uses to call `build-packages.yaml`.

## Keys and release tags

Job **Key rules and key tests** (`keys`):

1. `check-keys.sh` on `keys/`: one online key, plus the keys `keys/RECOVERY` and `keys/ROTATION` name. SECURITY.md lists the current and the recovery fingerprint.
2. `test-keys.sh`:
   - accepts the shapes `{online}`, `{online, recovery}`, `{online, next}`, `{online, next, recovery}`;
   - refuses a stray key, a stale or wrong marker, a wrong signer, the recovery key as signer or its secret in the gpg home, and an altered, unverified or unattested keyring package;
   - recovery signing and its verification, including tampered recovery repositories;
   - `Valid-Until`: present, an RFC 1123 date, exactly 14 days after `Date`, inside the signed text; a recovery index with no, an unbounded, an expired, a nearly expired (under 7 days), a future-dated or a malformed window refused;
   - two builds at different times give byte-identical `Packages*` and `.deb` files, while `Release`, `InRelease` and `Release.gpg` differ;
   - `check-index-freshness.sh` accepts a fresh index signed by the online or the recovery key, and refuses a stale, expired, unbounded, wrongly signed or error-page one.
3. [`test-release-tags.sh`](../../../../scripts/test-release-tags.sh), against a bare `file://` remote:
   - a tag per `pwsh` and `pwsh-preview` package, none for the keyring package, `~` written as `-`;
   - each tag annotated, on the given commit, by `github-actions[bot]`, verified with `gpgv` and `git tag -v`; an existing tag left alone; the next key and a passphrase-protected key accepted;
   - refused, leaving no tag: a stray or recovery key, a missing passphrase, no `SIGN_KEY`, no commit; and any tag that is lightweight, unsigned, misnamed, altered, doubly signed, recovery- or stray-signed, or points at a tree;
   - the push refused for an unsigned tag or a different remote tag of the same name, and deferred (exit 3) when the remote `main`'s workflows changed.
4. [`test-sign-release.sh`](../../../../scripts/test-sign-release.sh), offline with throwaway keys: the bundle handed from `assemble` to `sign`, `sign-release.sh sign`/`install`, and the release tag payloads (`payloads`, `sign-payloads`, `assemble`); anything altered, stale, linked or signed by another key is refused.

## Run the package (arm64)

Job **Run the package (arm64)** (`device-smoke`, `ubuntu-24.04-arm`) builds the current stable release, links Termux's glibc paths (`$TERMUX_PREFIX/glibc/lib`) to the runner's own glibc, installs the `.deb` into `/` and runs `pwsh` directly and through the `bin/pwsh` symlink, with ICU switched off. It proves the patched interpreter and rpath load and run; it does not replace [a run on a phone](../build.md#testing-on-a-device), which uses Termux's own glibc and libraries.

## Package build

Job **Package build** (`package`) builds the current stable release twice and compares byte for byte (a daily rebuild must not change `Packages`), and checks the patched loader and the symlink. It builds the keyring package twice and compares it too, and checks it ships `keys/` and the `signed-by` source. Then the SBOMs of both, an unsigned repository and the site assembly, and finally a repository signed with a throwaway key through the test-only `KEYRING_FILE`.

## Packaging scripts

Job **Packaging script tests** (`packaging-tests`), each refusal checked for its reason:

1. [`test-find-releases.sh`](../../../../scripts/test-find-releases.sh), with a stub `curl`: the highest version wins over the newest date; drafts and releases without the arm64 tarball are skipped; the preview only when its core version is newer; 7.10 above 7.9; `GITHUB_TOKEN` sent as a Bearer header, nothing without it. Refused: no stable release, an empty list, an HTTP error.
2. [`test-build-deb.sh`](../../../../scripts/test-build-deb.sh), with fake ELF tarballs and UTF-16 or UTF-8 checksums: control fields, patched interpreter and rpath, symlink, timestamps and modes, build record, byte-identical rebuilds, the revision from `packaging-revisions` (the committed file, a line, no line, no file). Refused: a bad package or tag, a malformed or repeated `packaging-revisions` line or an unreadable file, a missing or wrong checksum, no `patchelf`, `pwsh` or ELF, a bad `SOURCE_DATE_EPOCH`.
3. [`test-make-sboms.sh`](../../../../scripts/test-make-sboms.sh), with stub syft, sbom-tool and validator behind the real download-and-hash code: the eight files, SPDX 2.3, every file validated. Refused: a download failing its SHA-256, no build record or packages, a rejected document, a failing sbom-tool.
4. [`test-fetch-verified.sh`](../../../../scripts/test-fetch-verified.sh), with a stub `curl`: the shared download that make-sboms and the workflows use for their pinned tools. A matching hash is kept, a copy already there is not downloaded again, a wrong copy is replaced, every error is retried. Refused: a wrong hash, a failing download, missing arguments.
5. [`test-assemble-site.sh`](../../../../scripts/test-assemble-site.sh), with a local git history and a hand-made apt index: the status line, the documents table, the dates and the `?v=` hashes, exactly. Refused: a missing page, index, `Release`, `Valid-Until` or favicon, a shallow clone, an unclosed block, a bad version, an uncommitted document.

## Keep-alive and audit

1. **Schedule keep-alive tests** (`keepalive`): [`test-keepalive.sh`](../../../../scripts/test-keepalive.sh) runs [`keep-schedules-alive.sh`](../../../../scripts/keep-schedules-alive.sh) against a stub `gh`: which files count as scheduled; `refresh` enables active and inactivity-disabled workflows, never one turned off by hand; it fails when it had to re-enable one or an enable call fails; `--dry-run` writes nothing; `check` fails only on `disabled_inactivity`.
2. **Keep-alive commit and audit tests** (`keepalive-commit`): [`test-keepalive-commit.sh`](../../../../scripts/test-keepalive-commit.sh) runs [`keepalive-commit.sh`](../../../../scripts/keepalive-commit.sh) and [`audit-main-commits.sh`](../../../../scripts/audit-main-commits.sh) against local repositories, a bare `file://` remote and a stub `gh` (no network, no key).
   - The commit: pushed on a 40-day-old `main` with its status, skipped under 30 days, nothing pushed by `--dry-run`, rebuilt when `main` moves (at most 3 times), failing at once when a refused push is not a race; refused off `main` or without a loadable key (never printed).
   - The guard refuses: an extra file, a file named `keep.alive<newline>` or `<newline>` beside it, six kinds of wrong content, a merge, another committer or message, a symbolic link, a wrong parent.
   - The audit accepts a verified commit by the owner, a `web-flow` commit of a merged pull request and a keep-alive commit with its status. It flags anything else (no or an unmerged pull request, a wrong status, an extra file, another committer, an untrusted signature, a rewritten `main`) and fails when the pull requests cannot be read.
   - The issues: opened, updated, matched by exact title, closed when clean.

## Coverage

Job **Coverage** (`coverage`) runs every `scripts/test-*.sh` again with each Bash process traced (xtrace through `BASH_ENV`, to files in `RUNNER_TEMP`), and the Hypothesis tests under coverage.py. [`.github/scripts/coverage.py`](../../../../.github/scripts/coverage.py) then reports, per file and with the lines never run, in the job summary:

- the share of lines that start a command in `scripts/*.sh` and `scripts/lib/*.sh` (commands from shfmt's parser, `shfmt --to-json`; the test scripts are not counted);
- the share of statements in `scripts/*.py`.

It fails when Bash, Python or the total is under its floor (`COVERAGE_MIN_*` in `ci.yaml`: the measured coverage rounded down; raise them as tests are added, never lower them to let a change through). The traces hold every command's arguments, so the job only runs the tests and never uploads them.

Locally (needs `shfmt`): `python3 .github/scripts/coverage.py run out/trace -- bash scripts/test-build-deb.sh` for each test, then `python3 .github/scripts/coverage.py report out/trace`.

## Fuzzing

[`fuzz.yaml`](../../../../.github/workflows/fuzz.yaml), **Fuzz (Hypothesis)**: property-based fuzzing of [`spdx-build-view.py`](../../../../scripts/spdx-build-view.py) by [`tests/fuzz/`](../../../../tests/fuzz/test_spdx_build_view.py), with `dpkg-deb` stubbed.

[`clusterfuzzlite.yaml`](../../../../.github/workflows/clusterfuzzlite.yaml), **Fuzz (ClusterFuzzLite)**: coverage-guided fuzzing (Atheris, [`.clusterfuzzlite/`](../../../../.clusterfuzzlite/fuzz_spdx_build_view.py)) of the same script: 3 minutes on a pull request that touches it, 10 weekly. Not a required check (a path-filtered workflow cannot be one). It exists because Scorecard's Fuzzing check does not recognise Hypothesis. Its job blocks egress (GitHub and the `gcr.io` image hosts), passes no `github-token` and no secret to the third-party actions, and its base image is pinned by digest (Dependabot's `docker` ecosystem updates it). What is not pinned: the two action images (`clusterfuzzlite-build-fuzzers`, `-run-fuzzers`) that the pinned action commit pulls by the tag `v1`; only an update of the action can change that. The repository's Actions allowlist includes `google/clusterfuzzlite/*` for it.

1. Any JSON value, or a real build record with a field dropped or replaced, is refused with `BuildRecordError` (a one-line error and exit status 1 on the command line, never a traceback).
2. Any Depends field gives unique, clean package names (every alternative; no version, architecture or duplicate).
3. Every document has valid, unique SPDX identifiers (a Debian `+` becomes `-`), relationships only between its own elements, one package per dependency, lowercase SHA-256 checksums, purls that decode to the recorded values, and is the same twice apart from its creation time and namespace UUID.

300 inputs per property on every pull request and push to `main`; 20,000 weekly and by hand (`HYPOTHESIS_PROFILE`: `ci` or `long`). A failure prints the smallest failing input. Hypothesis is installed from `tools/fuzz/requirements.txt` with `--require-hashes`. Locally, from the repository root: `python -m pip install --require-hashes -r tools/fuzz/requirements.txt`, then `python -m unittest discover -s tests/fuzz -v`.

## DCO

[`dco.yaml`](../../../../.github/workflows/dco.yaml), **DCO**, on every pull request, with full history (`fetch-depth: 0`) and a read-only token:

1. [`test-dco.sh`](../../../../scripts/test-dco.sh) tests the checker on a local repository. Refused: no sign-off, another person's or address, one outside the trailer block, one unsigned commit among signed ones. Exempt: `main`'s commits merged in (only with the base branch given), Dependabot's in its own pull request, a genuine keep-alive commit.
2. [`check-dco.sh`](../../../../scripts/check-dco.sh) fails if a commit the pull request adds lacks a `Signed-off-by:` trailer naming its author ([Developer Certificate of Origin](../contributing.md#developer-certificate-of-origin)).

## Website

[`site.yaml`](../../../../.github/workflows/site.yaml) runs [`test-validate-site.sh`](../../../../scripts/test-validate-site.sh) before validating: fixture sites where each level of message, a bad stylesheet and a bad SVG must fail. The checks themselves: [workflows](workflows.md) and [website](../website.md#the-checks).
