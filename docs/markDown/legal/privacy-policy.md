# Privacy policy

*This page's last change (date and commit) comes from Git: see the [documents page](https://pwsh-termux.machlev.org/documents.html) or this file's history on GitHub.*

pwsh-termux collects **nothing** about you. This policy covers the website (`pwsh-termux.machlev.org`), the apt repository served from it, the GitHub repository and the packages. The short version is on the [website](https://pwsh-termux.machlev.org/privacy.html).

## What the project collects

Nothing: no accounts, forms, cookies, analytics, advertising or fingerprinting, and no JavaScript on the website. The packages send nothing anywhere when you install or run PowerShell. The maintainer receives no logs of who visits the site or downloads a package.

## What third parties may see

The project runs on other people's infrastructure, with its own logs and policies:

- **GitHub** hosts the repository, releases, issues and **GitHub Pages**, which serves the website and the apt repository. When you load a page or run `pkg update`, GitHub can see your IP address and request details and processes them under the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **Cloudflare** provides DNS for `machlev.org`, so DNS lookups for the domain pass through it. The domain is DNS only (your traffic is not proxied).
- **Your Termux mirror and the Termux glibc repository** are contacted by `pkg` as usual, under their own policies, when you install the dependencies.

If you open an issue, pull request or security advisory, GitHub stores what you write and shows it as GitHub does (issues and pull requests are public).

## PowerShell itself

The package installs Microsoft's PowerShell **unchanged**. Microsoft's build collects usage telemetry unless you opt out (`POWERSHELL_TELEMETRY_OPTOUT=1`) and can check for newer versions and print a notice (`POWERSHELL_UPDATECHECK=Off`). That is Microsoft's software, under [Microsoft's privacy statement](https://privacy.microsoft.com/); this project neither adds to it nor receives it. The [install page](https://pwsh-termux.machlev.org/install.html) shows how to turn both off.

## Your rights

The project holds no personal data about you, so there is nothing for it to give, correct or delete. For data held by GitHub, Cloudflare or Microsoft, use their own tools. You can edit or delete your issues and comments on GitHub.

## Children

The project is not directed at children and collects no data from anyone.

## Changes and contact

Changes to this policy are made in this file and are visible in the repository's history. Questions: open an [issue](https://github.com/EliorMachlev/pwsh-termux/issues). Security problems: [SECURITY.md](../../../SECURITY.md).
