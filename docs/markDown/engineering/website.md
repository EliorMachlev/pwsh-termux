# Website

`docs/*.html`, served by GitHub Pages at `pwsh-termux.machlev.org`, next to the apt repository. Plain HTML and one stylesheet: system fonts, a light and a dark palette that follow the system, no JavaScript, no forms. The mark ([`docs/favicon.svg`](../../favicon.svg), also in [`art/brand/`](../../../art/brand)) is a terminal prompt chevron and cursor; it is not Microsoft's PowerShell logo.

Pages: the home page ([`index.html`](../../index.html)), [`install.html`](../../install.html), [`privacy.html`](../../privacy.html), [`documents.html`](../../documents.html) and [`404.html`](../../404.html). Each page links to the Markdown handbook on GitHub; `docs/markDown/` is not served ([hosting](architecture/hosting.md)).

The install page has the install line, a *Verify it yourself* section (the two fingerprints from `keys/`, `gh attestation verify` with the flags the publish job uses, `gpgv` on `InRelease` and its `Valid-Until`), *Update*, *Uninstall*, *Questions* (key rotation and recovery as a user sees them, the *expired* error) and *If something goes wrong* (a missing `glibc-repo`, `NO_PUBKEY`, a non-arm64 device, an expired or not-yet-valid Release file). Keep the fingerprints there in step with [SECURITY.md](../../../SECURITY.md#signing-key), the README and `llms.txt`.

**Copying the install line without a script.** The command is in a `<pre class="copy">` whose code has `user-select: all`, so one tap or click selects the whole command and the browser's own copy takes it. A JavaScript copy button would need `script-src` in the Content Security Policy, which the site does not allow, so there is none.

**Generated blocks.** A page can mark fallback HTML between `<!-- generated:<name> -->` and `<!-- /generated:<name> -->`, each on a line of its own; [`assemble-site.sh`](../../../scripts/assemble-site.sh) replaces it at deploy time, and `site-check.py` checks each block opens and closes in order. `status` (home and install pages) becomes the versions the index serves and the index's last signing date and `Valid-Until`, read from `Packages` and `Release` of the repository being deployed; its fallback in `docs/` points to the releases. `documents` (the documents page) becomes a table of every Markdown document, the handbook in `docs/markDown/` and the top-level `README.md`, `SECURITY.md`, `CONTRIBUTING.md` and `NOTICE.md`, each with *Last updated &lt;date&gt; · &lt;short SHA&gt;* linked to the commit; `last-updated:<path>` (on the privacy page, for the full policy) is that line for one file.

**Dates of the Markdown documents.** No Markdown file holds its own "last updated" date: a file cannot name the commit that changes it, and a hand-written date goes stale. `assemble-site.sh` takes the date (`%cs`, the committer date) and SHA of `git log -1 -- <file>` at deploy time, so the Git history is the one source. That needs the full history: the deploying checkouts (`update.yaml`'s `publish`, `recover.yaml`, CI's package build) use `fetch-depth: 0`, and the script stops with an error in a shallow clone or outside a Git checkout instead of printing a wrong or empty date. A change to a top-level Markdown file does not start a deploy, so its date on the site follows at the next daily run.

**Nothing loads from another site.** Each page's Content Security Policy (a `<meta>` tag, as Pages sets no headers) is `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`: no scripts at all, styles and images from the site only. [`docs/.well-known/security.txt`](../../.well-known/security.txt) points to private vulnerability reporting (`Contact`) and to [SECURITY.md](../../../SECURITY.md) (`Policy`); the install page links it.

## The checks

[`.github/scripts/site-check.py`](../../../.github/scripts/site-check.py) (workflow: [`site.yaml`](../../../.github/workflows/site.yaml); also run before every deploy) fails on:

- a page without exactly one CSP `<meta>`, or one that lacks the directives above, allows scripts or `unsafe-*`, or names another origin;
- any `<script>`, `<form>`, `<base>`, `<iframe>`, `<object>`, `<embed>` or inline `on…=` handler;
- anything that loads from another site (`<link>`, `<img>`, `src`, `srcset`), or a plain-`http` link;
- a local link or asset that does not exist (paths the apt repository adds at deploy time, such as `/pwsh-termux.gpg`, are allowed);
- a generated block that is not opened and closed in order;
- a page without `lang`, a title, a viewport `<meta>`, exactly one `<h1>`, `<main id="main">`, a skip link, or an `alt` on an image;
- a `sitemap.xml` that does not list every page (except `404.html`), a `robots.txt` that does not point to it, a `CNAME` that is not the domain, or a `security.txt` with a wrong `Canonical` or an `Expires` less than 30 days away.

It runs on `docs/` in CI and before every deploy, and again on the assembled site (`repo/`, with the generated blocks filled) in CI's package build, `update.yaml` and `recover.yaml`. It uses only the standard library. The negative cases (an injected script, a missing file, a weakened CSP, a wrong `CNAME`) were tried by hand when it was written.

## Cache busting

Pages are cached for minutes and assets for hours, so at deploy time `assemble-site.sh` rewrites `"/style.css"` and `"/favicon.svg"` to `?v=<content hash>`. Nothing is stamped in the repository: the files in `docs/` stay plain.

## Search engines and AI assistants

Each page has Open Graph and Twitter card tags and a canonical link. [`robots.txt`](../../robots.txt) allows every crawler and points to [`sitemap.xml`](../../sitemap.xml), which lists every page but `404.html` (add a page there when you add one). [`llms.txt`](../../llms.txt) is a short, curated summary with links for AI assistants; keep its claims in step with the README and the install page. [`CITATION.cff`](../../../CITATION.cff) lets tools cite the project. The repository's description, homepage and topics are set in GitHub's settings.

## Updating `security.txt`

RFC 9116 asks for an `Expires` under a year ahead. [`renew-security-txt.yaml`](../../../.github/workflows/renew-security-txt.yaml) moves it to about eleven months ahead on the 1st of any month when fewer than four months are left, commits to `main` and starts the deploy. Renewing does not review the contact: do that when you see the commit. `site.yaml` still fails when fewer than 30 days remain, in case the renewal stops working.

## See also

- The live site: <https://pwsh-termux.machlev.org/>.
- How the site and the apt repository share one Pages deployment: [hosting](architecture/hosting.md).
- The CSP check and the workflows: [ci-cd.md](ci-cd.md).
