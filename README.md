<div align="center">

<a href="https://pwsh-termux.machlev.org/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="art/brand/mark-dark.svg">
    <img alt="The pwsh-termux mark: a terminal prompt chevron and cursor. Opens the pwsh-termux website" src="art/brand/mark-light.svg" width="128">
  </picture>
</a>

# pwsh-termux

**PowerShell 7 for Termux, installed with `pkg`.**<br>
An unofficial apt repository that follows Microsoft's PowerShell releases, verifies them, makes them run on Termux's glibc, signs them and keeps them up to date.

[![Latest release](https://img.shields.io/github/v/release/EliorMachlev/pwsh-termux?include_prereleases&label=release)](https://github.com/EliorMachlev/pwsh-termux/releases)
[![Update packages](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/update.yaml/badge.svg?event=schedule)](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/update.yaml)
[![CI](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/ci.yaml/badge.svg?branch=main&event=push)](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/ci.yaml)
[![CodeQL](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/codeql.yaml/badge.svg?branch=main&event=push)](https://github.com/EliorMachlev/pwsh-termux/actions/workflows/codeql.yaml)

[![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/EliorMachlev/pwsh-termux?label=openssf+scorecard)](https://securityscorecards.dev/viewer/?uri=github.com/EliorMachlev/pwsh-termux)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/16703/badge)](https://www.bestpractices.dev/projects/16703)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Termux aarch64](https://img.shields.io/badge/Termux-aarch64%20%C2%B7%20glibc-3DDC84?logo=android&logoColor=white)](docs/markDown/product/packages.md)
[![Signed apt repository](https://img.shields.io/badge/apt-signed%20(Ed25519)-blue)](SECURITY.md#signing-key)

**[Website](https://pwsh-termux.machlev.org/)** · [Install](https://pwsh-termux.machlev.org/install.html) · [Privacy](https://pwsh-termux.machlev.org/privacy.html) · [Releases](https://github.com/EliorMachlev/pwsh-termux/releases) · [Docs](docs/markDown/README.md)

</div>

---

## ✨ Highlights

- 📦 **Install with `pkg`.** `pkg install pwsh` after adding one repository; `pkg upgrade` keeps it current.
- 🔁 **Follows Microsoft.** A daily workflow publishes the highest **stable** release as `pwsh` and, while one is newer, the highest **preview or release candidate** as `pwsh-preview`. Releases are chosen by version, not date, because Microsoft backports patches to older lines.
- ✅ **Verified.** Each tarball must match the SHA-256 in Microsoft's `hashes.sha256` before anything is built from it.
- 🔏 **Signed.** apt verifies the index's Ed25519 signature on every `pkg update` ([fingerprint](SECURITY.md#signing-key)).
- 🧩 **Native.** The official glibc binary is patched to use Termux's glibc loader: no proot, no `glibc-runner` wrapper ([why](docs/markDown/engineering/architecture/packaging.md#why-patchelf-and-not-glibc-runner)).
- 🗃️ **Archived.** Every built `.deb` is kept as a GitHub release asset.
- 🪪 **Unofficial.** Not affiliated with Microsoft; Microsoft's files ship unchanged apart from two ELF headers ([NOTICE.md](NOTICE.md)).

## 📦 Get it

You need Termux on an **arm64 (aarch64)** device:

```bash
pkg install -y glibc-repo && curl -fsSL https://pwsh-termux.machlev.org/pwsh-termux-keyring.deb -o $TMPDIR/pwsh-termux-keyring.deb && dpkg -i $TMPDIR/pwsh-termux-keyring.deb && pkg update && pkg install pwsh
pkg install pwsh-preview        # optional: newest preview / release candidate
```

This enables the glibc repository, installs `pwsh-termux-keyring` (the public signing key and an apt source that trusts it for this repository only, with `signed-by`), then installs `pwsh`. To add the key and source by hand, see the [install page](https://pwsh-termux.machlev.org/install.html#by-hand).

Check that the keyring holds the signing key `7086 C70B 4A25 576F E0C0 CE77 E43F B41F 02D0 1FC8` and the offline recovery key `937A 3D41 5103 CFF8 9DCD A982 A4B4 5397 EEB6 D752` ([SECURITY.md](SECURITY.md#signing-key)):

```bash
pkg install gnupg
gpg --show-keys $PREFIX/share/keyrings/pwsh-termux-archive-keyring.gpg
```

Optionally verify the package's build provenance: `gh attestation verify $TMPDIR/pwsh-termux-keyring.deb --repo EliorMachlev/pwsh-termux --signer-workflow EliorMachlev/pwsh-termux/.github/workflows/build-packages.yaml --deny-self-hosted-runners`. To check the signed index with `gpgv`: [verify it yourself](https://pwsh-termux.machlev.org/install.html#verify).

Uninstall: `pkg remove pwsh pwsh-termux-keyring`, plus `pkg remove pwsh-preview` if you installed it. A new signing key arrives with `pkg upgrade`; download the keyring again for a key added by hand, if you did not run `pkg upgrade` within a rotation's 180 days, or if the online key is compromised while the recovery key is lost ([SECURITY.md](SECURITY.md#rotation-and-recovery), [questions](https://pwsh-termux.machlev.org/install.html#faq)). Troubleshooting (missing `glibc-repo`, `NO_PUBKEY`, a non-arm64 device, an *expired* Release file): the [install page](https://pwsh-termux.machlev.org/install.html#troubleshooting).

Packages ([details](docs/markDown/product/packages.md)):

1. `pwsh`: the highest stable PowerShell 7 release; command `pwsh`.
2. `pwsh-preview`: the highest preview or release candidate, only while newer than stable; command `pwsh-preview`, side by side with `pwsh`.
3. `pwsh-termux-keyring`: the public signing key ([`keys/`](keys)) and apt source; the install line installs it.

`pwsh` and `pwsh-preview` depend on `glibc`, `gcc-libs-glibc`, `libicu-glibc`, `openssl-glibc` and `zlib-glibc` from Termux's glibc repository.

## 🔧 How it works

```text
Microsoft's GitHub releases
        │  scripts/find-releases.sh   highest stable, newer preview
        ▼
official linux-arm64 tarball ──► SHA-256 check against hashes.sha256
        │  scripts/build-deb.sh       patch ELF loader, build the .deb
        ▼
pwsh_<version>_aarch64.deb      + pwsh-termux-keyring_<version>_all.deb
        │                               (scripts/build-keyring.sh, from keys/)
        │  scripts/build-repo.sh      apt index, Ed25519 signature
        │  scripts/assemble-site.sh   merge the website (docs/)
        ▼
GitHub Pages  ──►  https://pwsh-termux.machlev.org/   (+ each .deb as a release asset)
```

The pipeline is [`.github/workflows/update.yaml`](.github/workflows/update.yaml); [architecture](docs/markDown/engineering/architecture/README.md) explains each stage. Every release carries the `.deb`, a CycloneDX and three SPDX SBOMs and signed build provenance ([verify](SECURITY.md#software-bill-of-materials-sbom-and-build-provenance)).

## ⚠️ Limits

- **arm64 only**, on Termux with the glibc repository.
- **Only the current stable and preview are in the repository.** Older builds are release assets.
- **PowerShell is unchanged**, including Microsoft's telemetry and update notice; the [install page](https://pwsh-termux.machlev.org/install.html) shows how to switch them off.
- **The signed index is valid for 14 days** and re-signed daily. If the pipeline broke for longer, `pkg update` would report the Release file as *expired* rather than serve stale packages ([why](SECURITY.md#index-freshness-valid-until)).

## 🧱 Built with

Bash · `dpkg-deb` · [patchelf](https://github.com/NixOS/patchelf) · `jq` · Python (the site checks) · [GnuPG](https://gnupg.org/) · GitHub Actions and Pages

Every pull request passes 19 required checks, among them shellcheck, jactionlint, a real package build, tests with a coverage floor, CodeQL, zizmor, Gitleaks, Hypothesis fuzzing, lychee, typos, the website checks and a DCO sign-off. Every action is pinned to a commit; Dependabot keeps the pins current ([CI / CD](docs/markDown/engineering/ci-cd.md)).

## 📚 Documentation

Start at the [documentation index](docs/markDown/README.md), for example [architecture](docs/markDown/engineering/architecture/README.md), [build](docs/markDown/engineering/build.md) or [security](docs/markDown/engineering/security.md). The [website](https://pwsh-termux.machlev.org/) is the user-facing version.

## 🤝 Contributing

Bug fixes are welcome; for new features, open an issue first ([contributor guide](docs/markDown/engineering/contributing.md)). Report vulnerabilities privately, as [SECURITY.md](SECURITY.md) describes.

## ⚖️ Legal

[Privacy Policy](docs/markDown/legal/privacy-policy.md) · [Terms of Service](docs/markDown/legal/terms-of-service.md) · [Accessibility Statement](docs/markDown/legal/accessibility-statement.md) · [Compliance Posture](docs/markDown/legal/compliance-posture.md) · [SECURITY.md](SECURITY.md)

## 📄 License

PowerShell © Microsoft Corporation, MIT; what the packaging changes is in [NOTICE.md](NOTICE.md). "PowerShell" is a trademark of Microsoft; this project is not affiliated with or endorsed by Microsoft. Packaging scripts © pwsh-termux contributors, [MIT](LICENSE).
