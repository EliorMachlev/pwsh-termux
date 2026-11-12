# Compliance posture

*Last updated: 2026-11-12. This page describes how the maintainer reads the rules that may touch this project; it is not legal advice.*

pwsh-termux is a **non-commercial, volunteer, open-source** repackaging project. It sells nothing, is not run as a business, and processes no personal data. The sections below record where that matters.

## What the project is, for regulators

- **Maintainer:** an individual, Elior Machlev, acting privately.
- **The product:** Microsoft's PowerShell, redistributed unmodified apart from two ELF headers ([NOTICE.md](../../../NOTICE.md)). Microsoft is its manufacturer; this project is a downstream redistributor.
- **Distribution:** free, from GitHub Pages and GitHub Releases, worldwide.

## EU Cyber Resilience Act (Regulation (EU) 2024/2847)

The CRA applies to products with digital elements made available on the EU market **in the course of a commercial activity**; its text says free and open-source software developed or supplied outside a commercial activity is out of scope. As a non-monetized volunteer project, pwsh-termux is read as **out of scope**. It nonetheless follows the practices the CRA encourages: coordinated vulnerability disclosure with a stated timeline and private reporting ([SECURITY.md](../../../SECURITY.md)), signed releases, pinned and audited build steps, and a description of exactly what a package contains. If the project ever became commercial (for example, paid support), this page would be reviewed first.

## Trademark and affiliation

"PowerShell" is a Microsoft trademark. The project uses the name only to say which software is packaged (nominative use), says on every surface that it is unofficial and unaffiliated, uses its own name (`pwsh-termux`) and its own mark, which is not Microsoft's logo, and makes no claim of endorsement. The package names (`pwsh`, `pwsh-preview`) are the shell's command names.

## Licensing

PowerShell and the packaging scripts are both MIT. Every package carries Microsoft's license text and copyright notice, as MIT requires. The packages depend on, and do not bundle, the libraries from Termux's glibc repository (each under its own license).

## Export controls

PowerShell runs on .NET and uses cryptographic libraries. It is publicly available open-source software that Microsoft already publishes worldwide, and this project adds no cryptography of its own beyond using GnuPG to sign the repository. The maintainer's reading is that redistributing it falls under the usual treatment of publicly available open-source software, but export rules differ by country and change; users are responsible for their own jurisdiction's rules, and anyone relying on this page should take advice.

## Data protection (GDPR and similar)

The project does not process personal data ([privacy policy](privacy-policy.md)); GitHub, Cloudflare and Microsoft act under their own roles for what they log or collect. There is therefore no controller relationship, register of processing or data-subject process to run.

## Accessibility law

The website is built to WCAG 2.2 AA ([accessibility statement](accessibility-statement.md)). As a private, non-commercial site it is not within the scope of the European Accessibility Act or of public-sector accessibility rules, but follows them voluntarily.

## Other regimes

- **Digital services (DSA / DMA):** the project hosts no user content other than what GitHub itself hosts (issues and comments), and is not a platform or gatekeeper.
- **Financial, health and AI regulation:** not applicable; the project handles no money, health data, or AI systems.
- **Sanctions and embargoes:** GitHub's own restrictions apply to the hosting; the maintainer does not otherwise restrict access.
