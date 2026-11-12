# Privacy policy

*Last updated: 2026-11-12.*

pwsh-termux collects **nothing** about you. This policy covers the website (`pwsh-termux.machlev.org`), the apt repository served from it, the GitHub repository, and the packages. The short version is on the [website](https://pwsh-termux.machlev.org/privacy.html).

## What the project collects

Nothing. There are no accounts, no forms, no cookies, no analytics, no advertising, no fingerprinting, and no JavaScript on the website. The packages' scripts send nothing anywhere when you install or run PowerShell. The maintainer does not receive any logs of who visits the site or downloads a package.

## What third parties may see

The project runs on other people's infrastructure, which has its own logs and policies:

- **GitHub** hosts the repository, the releases, the issues and **GitHub Pages**, which serves the website and the apt repository. When you load a page or run `pkg update`, GitHub can see your IP address and request details, and processes them under the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **Cloudflare** provides the DNS for `machlev.org`. DNS lookups for the domain pass through it. The domain is configured as DNS only (no proxying of your traffic).
- **Your Termux mirror and the Termux glibc repository** are contacted by `pkg` as usual, under their own policies, when you install the dependencies.

If you open an issue, a pull request or a security advisory, what you write is stored by GitHub and visible as GitHub makes it visible (issues and pull requests are public).

## PowerShell itself

The package installs Microsoft's PowerShell **unchanged**. Microsoft's build collects usage telemetry unless you opt out (set `POWERSHELL_TELEMETRY_OPTOUT=1`) and can check for newer versions and print a notice (set `POWERSHELL_UPDATECHECK=Off`). That is Microsoft's software acting under [Microsoft's privacy statement](https://privacy.microsoft.com/); this project neither adds to it nor receives it. The [install page](https://pwsh-termux.machlev.org/install.html) shows how to turn both off.

## Your rights

Because the project holds no personal data about you, there is nothing for it to give, correct or delete. For data held by GitHub, Cloudflare or Microsoft, use those services' own tools. Issues and comments you wrote on GitHub can be edited or deleted by you there.

## Children

The project is not directed at children and collects no data from anyone.

## Changes and contact

Changes to this policy are made in this file and are visible in the repository's history. Questions: open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues). Security problems: [SECURITY.md](../../../SECURITY.md).
