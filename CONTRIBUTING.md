# Contributing

The full guide is [`docs/markDown/engineering/contributing.md`](docs/markDown/engineering/contributing.md): setup, branching, code style, the PR checklist and commits. The short version:

## Before you start

- **Bug fixes** are welcome. **New features and refactors:** open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues) first.
- Bash and Python (standard library only) for the scripts; branch from `origin/main`. Build and test locally as the [build guide](docs/markDown/engineering/build.md) describes; the pipeline is laid out in [architecture](docs/markDown/engineering/architecture/README.md).

## Before you open a PR

- Run `shellcheck --shell=bash --severity=style scripts/*.sh` and `python3 .github/scripts/site-check.py docs`; CI runs the rest ([CI / CD](docs/markDown/engineering/ci-cd.md)).
- Warnings get fixed, not suppressed. The agreed exceptions (currently none) are in [exceptions.md](docs/markDown/engineering/exceptions.md).
- Title the PR `type(scope): short description` (`fix(build-deb): handle a missing checksum`).

## Reporting a bug

Open a [GitHub issue](https://github.com/EliorMachlev/pwsh-termux/issues) with your device architecture, the package and version (`pkg list-installed | grep pwsh`), what you ran, and the output.

## Reporting a vulnerability

Don't open a public issue: follow [SECURITY.md](SECURITY.md).
