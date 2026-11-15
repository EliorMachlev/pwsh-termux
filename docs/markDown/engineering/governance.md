# Governance and roadmap

## Governance

pwsh-termux is a single-maintainer project: **[Elior Machlev](https://github.com/EliorMachlev)** owns the repository, the signing key, the domain and the decisions. There is no committee and no vote.

- **What the project packages** follows Microsoft's PowerShell releases ([architecture](architecture/releases.md)). It does not patch PowerShell's behaviour; the only changes are those in [NOTICE.md](../../../NOTICE.md).
- **Changes** reach `main` only through a pull request that passes every required check ([branching](branching.md)), the maintainer's included. Every commit is signed off under the [Developer Certificate of Origin](contributing.md#developer-certificate-of-origin), enforced by the required check *DCO*; there is no contributor license agreement.
- **Disputes** are settled by the maintainer, in the open, in the issue or pull request concerned. Conduct follows the [code of conduct](../../../CODE_OF_CONDUCT.md).
- **Becoming a maintainer:** someone with several accepted pull requests can be asked to become a collaborator. It has not happened yet.

## Roles and responsibilities

1. **Maintainer** (Elior Machlev): reviews and merges pull requests, owns the signing and recovery keys, answers [security reports](../../../SECURITY.md) within 7 days, publishes releases (the pipeline does it daily), keeps the domain and GitHub account secure.
2. **Contributor** (anyone): opens issues and pull requests following [CONTRIBUTING.md](../../../CONTRIBUTING.md).
3. **Dependabot and the pipeline** (automation): propose dependency updates; build and sign the repository on `main` ([CI / CD](ci-cd.md)).

## Continuity

This is the project's weak point. One person holds the access: the repository, the online signing key (as an Actions secret), the offline recovery key and the domain. Nobody else can take over today. What limits the damage:

- The pipeline runs unattended. The index is re-signed daily and expires after 14 days if that stops, which fails loudly for users instead of silently ([security](security.md)).
- A lost or stolen online key can be replaced through the offline recovery key ([recovery](release/signing-keys.md#recovery-with-the-offline-key)).
- Everything needed to rebuild is in the repository and documented ([release](release.md)).

A second maintainer with access to the repository, the domain and a copy of the recovery key would close the gap.

## Roadmap

Current and planned work, in no fixed order, without dates.

1. Keep up with PowerShell: stable and preview releases are picked up daily.
2. Keep every scanner at zero findings, with no suppressions ([exceptions](exceptions.md)).
3. Tests and coverage. Done: every packaging script has an offline test, and CI measures coverage of `scripts/` on every pull request and fails below a floor ([tests](ci-cd/tests.md)). Ongoing: keep coverage above those floors, and add a regression test with each bug fix.
4. Signed release tags. Done: every new release tag is an annotated tag signed with the online key and verified before it is pushed ([signed release tags](release/tags.md)); the one older tag, `pwsh-7.7.0-1`, stays unsigned.
5. Find a second maintainer.
6. Support other architectures only if Termux's glibc packages and PowerShell's builds allow it.

Not planned: patching PowerShell, supporting platforms other than Termux, running a service.
