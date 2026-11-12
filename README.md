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
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Termux aarch64](https://img.shields.io/badge/Termux-aarch64%20%C2%B7%20glibc-3DDC84?logo=android&logoColor=white)](docs/markDown/product/packages.md)
[![Signed apt repository](https://img.shields.io/badge/apt-signed%20(Ed25519)-blue)](SECURITY.md#signing-key)

**[Website](https://pwsh-termux.machlev.org/)** · [Install](https://pwsh-termux.machlev.org/install.html) · [Privacy](https://pwsh-termux.machlev.org/privacy.html) · [Releases](https://github.com/EliorMachlev/pwsh-termux/releases) · [Docs](docs/markDown/README.md)

</div>

---

## ✨ Highlights

| Feature | What you get |
|---|---|
| 📦 **Install with `pkg`** | `pkg install pwsh` after adding one repository; `pkg upgrade` keeps it current. No manual downloads, no launcher scripts. |
| 🔁 **Follows Microsoft** | A daily workflow reads Microsoft's GitHub releases and publishes the newest **stable** as `pwsh` and, while one is newer than stable, the newest **preview or release candidate** as `pwsh-preview`. Releases are chosen by version, not date, because Microsoft backports patches to older lines. |
| ✅ **Verified** | Each tarball is checked against the SHA-256 in Microsoft's own `hashes.sha256` (published as UTF-16, which the build decodes) before anything is built from it. |
| 🔏 **Signed** | The apt index is signed with a dedicated Ed25519 key, and apt verifies it on every `pkg update`. The fingerprint is in [SECURITY.md](SECURITY.md#signing-key). |
| 🧩 **Runs natively on Termux** | The official glibc binary is patched to use Termux's glibc loader, so `pwsh` starts directly: no proot, no `glibc-runner` wrapper ([why](docs/markDown/engineering/architecture/packaging.md#why-patchelf-and-not-glibc-runner)). |
| 🗃️ **Archived** | Every built `.deb` is kept as a GitHub release asset, so an older version is one download away. |
| 🪪 **Honest about what it is** | Unofficial, not affiliated with Microsoft; the package ships Microsoft's files unchanged apart from two ELF headers ([NOTICE.md](NOTICE.md)). |

## 📦 Get it

You need Termux on an **arm64 (aarch64)** device. Then:

```bash
pkg install glibc-repo          # the glibc package repository, if you have not enabled it yet

curl -fsSL https://pwsh-termux.machlev.org/pwsh-termux.gpg \
  -o $PREFIX/etc/apt/trusted.gpg.d/pwsh-termux.gpg
echo "deb https://pwsh-termux.machlev.org stable main" \
  > $PREFIX/etc/apt/sources.list.d/pwsh-termux.list

pkg update
pkg install pwsh                # stable
pkg install pwsh-preview        # optional: newest preview / release candidate
```

Check the key you downloaded has the fingerprint `7086 C70B 4A25 576F E0C0 CE77 E43F B41F 02D0 1FC8` (`gpg --show-keys $PREFIX/etc/apt/trusted.gpg.d/pwsh-termux.gpg`). Troubleshooting, updating and removing: the [install page](https://pwsh-termux.machlev.org/install.html).

| Package | Command | Follows |
|---|---|---|
| `pwsh` | `pwsh` | The highest stable PowerShell 7 release |
| `pwsh-preview` | `pwsh-preview` | The highest preview / release candidate, only while it is newer than stable; installs side by side with `pwsh` |

Both depend on `glibc`, `gcc-libs-glibc`, `libicu-glibc`, `openssl-glibc` and `zlib-glibc` from Termux's glibc repository. Details: [packages](docs/markDown/product/packages.md).

## 🔧 How it works

```text
Microsoft's GitHub releases
        │  scripts/find-releases.sh   highest stable, newer preview
        ▼
official linux-arm64 tarball ──► SHA-256 check against hashes.sha256
        │  scripts/build-deb.sh       patch ELF loader, build the .deb
        ▼
pwsh_<version>_aarch64.deb
        │  scripts/build-repo.sh      apt index, Ed25519 signature
        │  scripts/assemble-site.sh   merge the website (docs/)
        ▼
GitHub Pages  ──►  https://pwsh-termux.machlev.org/   (+ each .deb as a release asset)
```

The whole pipeline is [`.github/workflows/update.yaml`](.github/workflows/update.yaml); [architecture](docs/markDown/engineering/architecture/README.md) explains each stage.

## ⚠️ Limits worth knowing

- **arm64 only**, and only on Termux with the glibc repository: the packages are built for `aarch64` against Termux's glibc paths.
- **The repository holds the current stable and preview only.** Older builds are release assets, not apt candidates.
- **PowerShell is unchanged**, including Microsoft's telemetry and update notice. How to switch them off: the [install page](https://pwsh-termux.machlev.org/install.html).
- **Not post-quantum.** No quantum-resistant signature is possible in apt today; see [SECURITY.md](SECURITY.md#signing-key).

## 🧱 Built with

Bash · `dpkg-deb` · [patchelf](https://github.com/NixOS/patchelf) · `jq` · Python (the site checks) · [GnuPG](https://gnupg.org/) · GitHub Actions and Pages

Checked on every change by shellcheck, actionlint, a real package build, CodeQL (workflows), zizmor, Gitleaks and the docs checks (lychee, typos); every action is pinned to a commit and Dependabot keeps the pins current. See [CI / CD](docs/markDown/engineering/ci-cd.md).

## 📚 Documentation

Start at the [documentation index](docs/markDown/README.md): [architecture](docs/markDown/engineering/architecture/README.md), [build](docs/markDown/engineering/build.md), [release](docs/markDown/engineering/release.md), [CI / CD](docs/markDown/engineering/ci-cd.md), [security](docs/markDown/engineering/security.md) and the [website](docs/markDown/engineering/website.md). The [website](https://pwsh-termux.machlev.org/) is the user-facing version.

## 🤝 Contributing

Bug fixes are welcome; for new features, open an issue first. See the [contributor guide](docs/markDown/engineering/contributing.md).

Found a vulnerability? Please report it privately, as [SECURITY.md](SECURITY.md) describes.

## ⚖️ Legal

[Privacy Policy](docs/markDown/legal/privacy-policy.md) · [Terms of Service](docs/markDown/legal/terms-of-service.md) · [Accessibility Statement](docs/markDown/legal/accessibility-statement.md) · [Compliance Posture](docs/markDown/legal/compliance-posture.md) · [SECURITY.md](SECURITY.md)

## 📄 License

pwsh-termux packages [PowerShell](https://github.com/PowerShell/PowerShell) by Microsoft; [NOTICE.md](NOTICE.md) sums up what is and is not changed. "PowerShell" is a trademark of Microsoft, and this project is not affiliated with or endorsed by Microsoft.

PowerShell © Microsoft Corporation, MIT. Packaging scripts © pwsh-termux contributors, licensed under [MIT](LICENSE).
