# pwsh-termux documentation

The user-facing side is the [website](https://pwsh-termux.machlev.org/) and the [README](../../README.md); this folder is for contributors and anyone auditing the project.

## Product

- [Packages](product/packages.md): `pwsh`, `pwsh-preview` and `pwsh-termux-keyring`, versions, dependencies, what is installed where, pinning and downgrading

## Engineering

- [Contributing](engineering/contributing.md): setup, tests and coverage, rules, PR checklist (short version: [CONTRIBUTING.md](../../CONTRIBUTING.md))
- [Architecture](engineering/architecture/README.md): the pipeline and its rules, then [releases](engineering/architecture/releases.md), [packaging](engineering/architecture/packaging.md), [repository](engineering/architecture/repository.md) and [hosting](engineering/architecture/hosting.md)
- [Build](engineering/build.md): building and testing locally, the Termux quirks
- [Release](engineering/release.md): how a release happens, then [setup](engineering/release/setup.md), [provenance](engineering/release/provenance.md), [tags](engineering/release/tags.md) and [signing keys](engineering/release/signing-keys.md); releases are on [GitHub](https://github.com/EliorMachlev/pwsh-termux/releases)
- [CI / CD](engineering/ci-cd.md): the rules every workflow follows, then [workflows](engineering/ci-cd/workflows.md), [tests](engineering/ci-cd/tests.md), [rulesets](engineering/ci-cd/rulesets.md), [keep-alive](engineering/ci-cd/keepalive.md), [audit](engineering/ci-cd/audit.md), [Dependabot](engineering/ci-cd/dependabot.md) and [troubleshooting](engineering/ci-cd/troubleshooting.md)
- [Branches and the pipeline](engineering/branching.md): `main`, pull requests, and which checks run where
- [Security](engineering/security.md): supply chain, secrets, signing, code analysis
- [Governance and roadmap](engineering/governance.md): who decides, roles, continuity, what is planned
- [Exceptions](engineering/exceptions.md): the only suppressed findings, and why
- [Website](engineering/website.md): the GitHub Pages site

## Legal and policy

- [Privacy policy](legal/privacy-policy.md), [terms of service](legal/terms-of-service.md), [accessibility statement](legal/accessibility-statement.md), [compliance posture](legal/compliance-posture.md)
- [Code of conduct](../../CODE_OF_CONDUCT.md)
- [Security policy](../../SECURITY.md): reporting a vulnerability, supported versions, the signing key
- [NOTICE](../../NOTICE.md): the upstream project and what the packaging changes
