# Website

`docs/*.html`, served by GitHub Pages at `pwsh-termux.machlev.org` next to the apt repository ([hosting](architecture/hosting.md)). Plain HTML and one stylesheet: system fonts, light and dark palettes that follow the system, no JavaScript, no forms. The mark ([`docs/favicon.svg`](../../favicon.svg), also in [`art/brand/`](../../../art/brand)) is a prompt chevron and cursor, not Microsoft's PowerShell logo.

## Pages

1. [`index.html`](../../index.html): the home page: quick start, stable or preview, how it works (diagram), why trust it.
2. [`install.html`](../../install.html): *Set up the repository* (once), *Stable*, *Preview*; *Update*; *Uninstall*; *Verify it yourself* (the two fingerprints from `keys/`, `gh attestation verify` with the publish job's flags, `gpgv` on `InRelease` and its `Valid-Until`); *Add the key by hand*; *What happens when the signing key changes?*; *If something goes wrong* (missing `glibc-repo`, `NO_PUBKEY`, a non-arm64 device, an expired or not-yet-valid Release file).
3. [`privacy.html`](../../privacy.html): the short privacy policy.
4. [`documents.html`](../../documents.html): every Markdown document with its last change.
5. [`404.html`](../../404.html).

Each page links to the Markdown handbook on GitHub; `docs/markDown/` is not served. Keep the install page's fingerprints in step with [SECURITY.md](../../../SECURITY.md#signing-key), `INSTALL.md` and `llms.txt`.

The install command sits in a `<pre class="copy">` whose code has `user-select: all`: one tap selects it all for the browser's own copy. It wraps instead of scrolling sideways, so the whole command shows on a phone; the soft wraps are not copied. A copy button would need JavaScript, which the CSP forbids.

## Design

`style.css` follows Apple's interface guidelines as far as plain CSS allows: the system font with tracking and leading set per size and balanced headlines, a light grey page with raised white tiles (black and dark grey in dark mode), dark code blocks in both schemes, pill buttons that shrink on the press itself with a spring-shaped easing (`linear()`), a translucent sticky bar on wide screens, hover effects only with a fine pointer, and 44px touch targets. `color-scheme: light dark` on `:root` and a `prefers-color-scheme: dark` block switch the palette with the system; there is no theme switch, since it would need a script. Reduced motion (a change of shade instead of the shrink), reduced transparency, more contrast and forced colours (real edges instead of shadows) each get a plainer version. The stylesheet is ordered from general to specific, ending with the header bar, so `no-descending-specificity` holds without exceptions.

The markup follows the same pattern on every page: a `hero` (small `eyebrow` label, one large headline, a short lead, a pill button beside a `more` text link that ends in a chevron), then `band` sections with a centred headline, then `card` tiles (home page) or `panel` sections (install, privacy, documents). The install page opens with a `toc` row of pills that jump to its sections. Sections are plain `<section>` elements with an `id` on their heading for links; they carry no `aria-label` or `aria-labelledby`, which would turn each into a landmark region. A command is a bare `<pre class="copy">` with no role or label. The key fingerprints on the install page are a `<dl class="keys">`, one name and value per key. The footer is a labelled directory in three columns, with a breadcrumb on inner pages and the legal text last. Keep the generated-block markers alone on their lines, flush left.

## Diagrams

The home and install pages show each flow as a numbered list of steps (`<figure class="flow">`, an `<ol>`): plain text, so it follows the palette, forced colours, zoom and screen readers, and needs no image or script. In `style.css` each step lights up in turn, once, then stays lit (a CSS animation with a delay per step, so a list longer than seven needs another `nth-child` rule). A checkbox before the list pauses it with `:has(input:checked)` and `animation-play-state` (WCAG 2.2.2, since the run lasts more than five seconds); with reduced motion the list is shown finished and the checkbox is hidden. The Mermaid source stays in a `<details>` fold-out below, for readers who want it.

The README and `INSTALL.md` still use the animated GIFs in [`docs/img/`](../../img), because GitHub renders no Mermaid in its mobile browsers and app. The steps are drawn by [`tools/diagrams/gen.mjs`](../../../tools/diagrams/gen.mjs), which also writes the matching Mermaid source: change the steps there and update the `<ol>` lists, the Mermaid blocks and the GIFs together ([how to run it](build.md#regenerate-the-diagrams)). Only the 640-wide `<name>.gif` files are used.

## Generated blocks

A page can mark fallback HTML between `<!-- generated:<name> -->` and `<!-- /generated:<name> -->`, each on its own line; [`assemble-site.sh`](../../../scripts/assemble-site.sh) replaces it at deploy time:

1. `status` (home and install pages): the versions the index serves, its last signing date and `Valid-Until`, from the deployed `Packages` and `Release`. The fallback points to the releases.
2. `documents` (documents page): a table of the handbook in `docs/markDown/` plus the top-level `README.md`, `INSTALL.md`, `SECURITY.md`, `CONTRIBUTING.md` and `NOTICE.md`, each with *Last updated &lt;date&gt; · &lt;short SHA&gt;* linked to the commit.
3. `last-updated:<path>` (privacy page, for the full policy): that line for one file.

No Markdown file holds its own date (a file cannot name the commit that changes it). The date (`%cs`) and SHA come from `git log -1 -- <file>` at deploy time, so the deploying checkouts use `fetch-depth: 0`; the script stops in a shallow clone, outside Git, or for an uncommitted document rather than print a wrong or empty date ([`test-assemble-site.sh`](../../../scripts/test-assemble-site.sh)). A change to a top-level Markdown file does not trigger a deploy; its date updates at the next daily run.

## Nothing loads from another site

Each page's Content Security Policy is a `<meta>` tag (Pages sets no headers): `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`. No scripts; styles and images from the site only.

[`docs/.well-known/security.txt`](../../.well-known/security.txt) points to private vulnerability reporting (`Contact`) and to [SECURITY.md](../../../SECURITY.md) (`Policy`); the install page links it.

## Cache busting

At deploy time the stylesheet and icon references get a `?v=<content hash>` ([hosting](architecture/hosting.md#what-is-deployed)).

## Search engines and AI assistants

1. Each page has Open Graph and Twitter card tags and a canonical link.
2. [`robots.txt`](../../robots.txt) allows every crawler and points to [`sitemap.xml`](../../sitemap.xml), which lists every page except `404.html`; add new pages there.
3. [`llms.txt`](../../llms.txt) is a short, curated summary for AI assistants; keep it in step with the README, `INSTALL.md` and the install page.
4. [`CITATION.cff`](../../../CITATION.cff) lets tools cite the project.

The repository's description, homepage and topics are set in GitHub's settings.

## The checks

[`site-check.py`](../../../.github/scripts/site-check.py) enforces the CSP, the structure, local links and the metadata files; vnu and Stylelint validate the HTML, CSS and SVG with no message filtered. What each checks and where it runs: [website checks](website-checks.md).

## Updating security.txt

RFC 9116 asks for an `Expires` under a year ahead. On the 1st of each month [`renew-security-txt.yaml`](../../../.github/workflows/renew-security-txt.yaml) checks it; with fewer than four months left it opens (or comments on) the issue *Renew security.txt* and fails. Then:

1. Run the issue's command, which moves `Expires` about eleven months ahead, runs `site-check.py` and makes a signed commit.
2. Check the contact and policy lines, and open a pull request; its merge deploys the site.
3. The next run with more than four months left closes the issue.

The workflow cannot commit the date itself: the [rulesets](ci-cd/rulesets.md) require signed commits and pull requests and refuse new branches, and GitHub Actions cannot bypass them in a personal repository, so it holds only `issues: write`. `site-check.py` also fails when fewer than 30 days remain.
