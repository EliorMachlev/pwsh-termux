# Compliance posture

*How the maintainer reads the rules that may touch this project; not legal advice. This page's last change (date and commit) comes from Git: see the [documents page](https://pwsh-termux.machlev.org/documents.html) or this file's history on GitHub.*

pwsh-termux is a **non-commercial, volunteer, open-source** repackaging project. It sells nothing, is not run as a business, and processes no personal data.

## What the project is

- **Maintainer:** an individual, Elior Machlev, acting privately.
- **Product:** Microsoft's PowerShell, redistributed unmodified apart from two ELF headers ([NOTICE.md](../../../NOTICE.md)). Microsoft is the manufacturer; this project is a downstream redistributor.
- **Distribution:** free, worldwide, from GitHub Pages and GitHub Releases.

## EU Cyber Resilience Act (Regulation (EU) 2024/2847)

The CRA applies to products with digital elements made available on the EU market **in the course of a commercial activity**; its text excludes free and open-source software developed or supplied outside one. As a non-monetized volunteer project, pwsh-termux is read as **out of scope**. It still follows the practices the CRA encourages: coordinated vulnerability disclosure with private reporting and a stated timeline ([SECURITY.md](../../../SECURITY.md)), signed releases, pinned and audited build steps, and an exact description of each package's content. If the project ever becomes commercial (for example, paid support), this page is reviewed first.

## Trademark and affiliation

"PowerShell" is a Microsoft trademark. The project uses the name only to say which software is packaged (nominative use), states on every surface that it is unofficial and unaffiliated, uses its own name (`pwsh-termux`) and its own mark (not Microsoft's logo), and claims no endorsement. The package names (`pwsh`, `pwsh-preview`) are the shell's command names.

## Licensing

PowerShell and the packaging scripts are both MIT. Every package carries Microsoft's license text and copyright notice, as MIT requires. The packages depend on, and do not bundle, the libraries from Termux's glibc repository, each under its own license.

## Export controls

PowerShell runs on .NET and uses cryptographic libraries. It is publicly available open-source software that Microsoft already publishes worldwide; this project adds no cryptography beyond using GnuPG to sign the repository. The maintainer reads redistributing it as falling under the usual treatment of publicly available open-source software, but export rules differ by country and change: users are responsible for their own jurisdiction's rules, and anyone relying on this page should take advice.

## Data protection (GDPR and similar)

The project processes no personal data ([privacy policy](privacy-policy.md)); GitHub, Cloudflare and Microsoft act in their own roles for what they log or collect. So there is no controller relationship, register of processing or data-subject process to run.

## Accessibility law

The website is built to WCAG 2.2 AA ([accessibility statement](accessibility-statement.md)). As a private, non-commercial site it is outside the European Accessibility Act and public-sector accessibility rules, but follows them voluntarily.

## Other regimes

- **Digital services (DSA / DMA):** the project hosts no user content beyond what GitHub hosts (issues and comments), and is not a platform or gatekeeper.
- **Financial, health and AI regulation:** not applicable; the project handles no money, health data or AI systems.
- **Sanctions and embargoes:** GitHub's restrictions apply to the hosting; the maintainer adds none.
