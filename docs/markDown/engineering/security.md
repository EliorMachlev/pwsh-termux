# Security

Reporting a vulnerability, supported versions and the signing key: [SECURITY.md](../../../SECURITY.md). This page indexes the engineering posture behind it.

The goal: a user who installs `pwsh` with `pkg` gets Microsoft's PowerShell as built by this pipeline, and nothing else.

1. [Threat model](security/threat-model.md): each threat, its mitigation and what is left over.
2. [Assurance case](security/assurance-case.md): the claim above, the argument for it and the accepted weaknesses.
3. [Supply chain](security/supply-chain.md): input verification, reproducible builds, SBOMs, pinned actions, network, code analysis.

## Secrets

- **`GPG_PRIVATE_KEY`**: the signing key, passphrase-protected. A secret of the environment `signing` (deployment branches: `main` only), read by one step of `update.yaml`; pull requests cannot read it. Its public half is in `keys/` ([setup](release.md#one-time-setup)).
- **`GPG_PASSPHRASE`**: its passphrase, in the same environment and step. Written to a mode-600 file under `RUNNER_TEMP` for gpg's `--passphrase-file` and removed after the step; never in an argument, the log or a later step. Whoever can read the key can read it too.
- **`KEEPALIVE_DEPLOY_KEY`**: the private half of the repository's only deploy key (read-write), a secret of the environment `keepalive` (`main` only), used by one step of `keepalive-commit.yaml` and piped into an `ssh-agent`, never written to disk ([keep-alive commit](ci-cd.md#keep-alive-commit), [rotation](release.md#rotating-the-keep-alive-deploy-key)).
- **`GITHUB_TOKEN`**: per run, permissions set per job ([CI / CD](ci-cd.md)). `actions: write` only on the three keep-alive jobs; `statuses: write` only on the keep-alive commit's job; `contents: write` only on `update.yaml`'s `publish` job, which pushes the signed release tags and creates the releases.

There are no other credentials: no personal access tokens, no third-party services.
