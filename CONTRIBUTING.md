# Contributing

Full guide: [`docs/markDown/engineering/contributing.md`](docs/markDown/engineering/contributing.md). The short version:

## Before you start

- **Bug fixes** are welcome. For **new features and refactors**, open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues) first.
- Scripts are Bash, and Python (standard library only). Branch from `origin/main`; build and test as the [build guide](docs/markDown/engineering/build.md) describes. The pipeline: [architecture](docs/markDown/engineering/architecture/README.md).

## Before you open a pull request

1. Run `shellcheck --shell=bash --severity=style scripts/*.sh scripts/lib/*.sh` and `python3 .github/scripts/site-check.py docs`; CI runs the rest ([CI / CD](docs/markDown/engineering/ci-cd.md)).
2. Add a test for new behaviour and bug fixes ([tests](docs/markDown/engineering/contributing.md#tests)).
3. Fix warnings; never suppress them ([exceptions.md](docs/markDown/engineering/exceptions.md) lists the agreed ones).
4. Title it `type(scope): short description`, e.g. `fix(build-deb): handle a missing checksum`.
5. **Sign off every commit** with `git commit -s`. The `Signed-off-by:` trailer certifies the [Developer Certificate of Origin](https://developercertificate.org/): you wrote the change or have the right to submit it under the [license](LICENSE). The required *DCO* check fails without it; fix with `git rebase --signoff origin/main` and push again ([details](docs/markDown/engineering/contributing.md#developer-certificate-of-origin)).

Everyone follows the [code of conduct](CODE_OF_CONDUCT.md); who decides what: [governance](docs/markDown/engineering/governance.md).

## Reporting a bug

Open a [GitHub issue](https://github.com/EliorMachlev/pwsh-termux/issues) with your device architecture, the package and version (`pkg list-installed | grep pwsh`), what you ran, and the output.

## Reporting a vulnerability

Don't open a public issue: follow [SECURITY.md](SECURITY.md).
