# Governance and roadmap

## Governance

pwsh-termux is a single-maintainer project: **[Elior Machlev](https://github.com/EliorMachlev)** owns the repository, the signing key, the domain and the decisions. There is no committee and no vote.

- **What the project packages** follows Microsoft's PowerShell releases ([architecture](architecture/releases.md)). It does not patch PowerShell's behaviour; the only changes are the ones in [NOTICE.md](../../../NOTICE.md).
- **Changes** reach `main` only through a pull request that passes every required check ([branching](branching.md)). The maintainer's own changes follow the same rule.
- **Disputes** are settled by the maintainer, in the open, in the issue or pull request concerned. Conduct matters follow the [code of conduct](../../../CODE_OF_CONDUCT.md).
- **Becoming a maintainer:** someone who has contributed several accepted pull requests can be asked to become a collaborator. It has not happened yet.

## Roles and responsibilities

| Role | Who | Does |
|---|---|---|
| **Maintainer** | Elior Machlev | Reviews and merges pull requests, owns the signing and recovery keys, answers [security reports](../../../SECURITY.md) within 7 days, publishes releases (the pipeline does it daily), keeps the domain and GitHub account secure. |
| **Contributor** | anyone | Opens issues and pull requests following [CONTRIBUTING.md](../../../CONTRIBUTING.md). |
| **Dependabot, the pipeline** | automation | Propose dependency updates, build and sign the repository on `main` ([ci-cd](ci-cd.md)). |

## Continuity

This is the project's weak point and is stated plainly. One person holds the access: the repository, the online signing key (as an Actions secret), the offline recovery key and the domain. Nobody else can take over today. What exists to limit the damage:

- The pipeline runs unattended; the index re-signs daily and expires after 14 days if it stops, which fails loudly for users instead of silently ([security](security.md)).
- Recovery from a lost or stolen online key through the offline key ([release](release.md#recovery-with-the-offline-key)).
- Everything needed to rebuild is in the repository and documented ([release](release.md)).

Adding a second maintainer with access to the repository, the domain and a copy of the recovery key would close the gap.

## Roadmap

Current and planned work, in no fixed order. There are no dates.

1. Keep up with PowerShell: stable and preview releases are picked up daily.
2. Keep every scanner at zero findings, with no suppressions ([exceptions](exceptions.md)).
3. Add automated tests for the packaging scripts beyond the key, keep-alive and site checks, and measure coverage.
4. Sign release tags.
5. Find a second maintainer.
6. Support other architectures only if Termux's glibc packages and PowerShell's builds allow it.

Not planned: patching PowerShell, supporting platforms other than Termux, running a service.
