# Website

`docs/*.html`, served by GitHub Pages at `pwsh-termux.machlev.org` next to the apt repository ([hosting](architecture/hosting.md)). Plain HTML and one stylesheet: system fonts, light and dark palettes that follow the system, no JavaScript, no forms. The mark ([`docs/favicon.svg`](../../favicon.svg), also in [`art/brand/`](../../../art/brand)) is a prompt chevron and cursor, not Microsoft's PowerShell logo.

## Pages

1. [`index.html`](../../index.html): the home page.
2. [`install.html`](../../install.html): the install line; *Verify it yourself* (the two fingerprints from `keys/`, `gh attestation verify` with the publish job's flags, `gpgv` on `InRelease` and its `Valid-Until`); *Update*; *Uninstall*; *Questions* (key rotation and recovery, the *expired* error); *If something goes wrong* (missing `glibc-repo`, `NO_PUBKEY`, a non-arm64 device, an expired or not-yet-valid Release file).
3. [`privacy.html`](../../privacy.html): the short privacy policy.
4. [`documents.html`](../../documents.html): every Markdown document with its last change.
5. [`404.html`](../../404.html).

Each page links to the Markdown handbook on GitHub; `docs/markDown/` is not served. Keep the install page's fingerprints in step with [SECURITY.md](../../../SECURITY.md#signing-key), the README and `llms.txt`.

The install command sits in a `<pre class="copy">` whose code has `user-select: all`: one tap selects it all for the browser's own copy. A copy button would need JavaScript, which the CSP forbids.

## Generated blocks

A page can mark fallback HTML between `<!-- generated:<name> -->` and `<!-- /generated:<name> -->`, each on its own line; [`assemble-site.sh`](../../../scripts/assemble-site.sh) replaces it at deploy time:

1. `status` (home and install pages): the versions the index serves, its last signing date and `Valid-Until`, from the deployed `Packages` and `Release`. The fallback points to the releases.
2. `documents` (documents page): a table of the handbook in `docs/markDown/` plus the top-level `README.md`, `SECURITY.md`, `CONTRIBUTING.md` and `NOTICE.md`, each with *Last updated &lt;date&gt; · &lt;short SHA&gt;* linked to the commit.
3. `last-updated:<path>` (privacy page, for the full policy): that line for one file.

No Markdown file holds its own date: a file cannot name the commit that changes it, and a typed date goes stale. The date (`%cs`) and SHA come from `git log -1 -- <file>` at deploy time, which needs full history: the deploying checkouts use `fetch-depth: 0`, and the script stops in a shallow clone, outside Git, or for an uncommitted document rather than print a wrong or empty date ([`test-assemble-site.sh`](../../../scripts/test-assemble-site.sh)). A change to a top-level Markdown file does not trigger a deploy, so its date updates at the next daily run.

## Nothing loads from another site

Each page's Content Security Policy is a `<meta>` tag (Pages sets no headers): `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`. No scripts; styles and images from the site only.

[`docs/.well-known/security.txt`](../../.well-known/security.txt) points to private vulnerability reporting (`Contact`) and to [SECURITY.md](../../../SECURITY.md) (`Policy`); the install page links it.

## Cache busting

At deploy time the stylesheet and icon references get a `?v=<content hash>` ([hosting](architecture/hosting.md#what-is-deployed)).

## Search engines and AI assistants

1. Each page has Open Graph and Twitter card tags and a canonical link.
2. [`robots.txt`](../../robots.txt) allows every crawler and points to [`sitemap.xml`](../../sitemap.xml), which lists every page except `404.html`; add new pages there.
3. [`llms.txt`](../../llms.txt) is a short, curated summary for AI assistants; keep it in step with the README and the install page.
4. [`CITATION.cff`](../../../CITATION.cff) lets tools cite the project.

The repository's description, homepage and topics are set in GitHub's settings.

## The checks

[`site-check.py`](../../../.github/scripts/site-check.py) enforces the CSP, the structure, local links and the metadata files; vnu and Stylelint validate the HTML, CSS and SVG with no message filtered. What each checks and where it runs: [website checks](website-checks.md).

## Updating security.txt

RFC 9116 asks for an `Expires` under a year ahead. On the 1st of each month [`renew-security-txt.yaml`](../../../.github/workflows/renew-security-txt.yaml) checks it: with fewer than four months left, it opens (or comments on) the issue *Renew security.txt* and fails. The issue gives the command that moves the date about eleven months ahead (a `sed` on `Expires`, `site-check.py`, a signed commit). Check the contact and policy, open a pull request, and its merge deploys the site. The next run with more than four months left closes the issue.

The workflow cannot commit the date itself: the rulesets require signed commits on every branch, pull requests with passing checks on `main`, and refuse new branches outside `dependabot/`; GitHub Actions cannot bypass them in a personal repository ([rulesets](release.md#rulesets)). So its only write permission is `issues: write`. `site-check.py` also fails when fewer than 30 days remain, in case the issue is missed.
