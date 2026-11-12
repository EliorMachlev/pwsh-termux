# Website

`docs/*.html`, served by GitHub Pages at `pwsh-termux.machlev.org`, next to the apt repository. Plain HTML and one stylesheet: system fonts, a light and a dark palette that follow the system, no JavaScript, no forms. The mark ([`docs/favicon.svg`](../../favicon.svg), also in [`art/brand/`](../../../art/brand)) is a terminal prompt chevron and cursor; it is not Microsoft's PowerShell logo.

Pages: the home page ([`index.html`](../../index.html)), [`install.html`](../../install.html), [`privacy.html`](../../privacy.html) and [`404.html`](../../404.html). Each page links to the Markdown handbook on GitHub; `docs/markDown/` is not served ([hosting](architecture/hosting.md)).

**Nothing loads from another site.** Each page's Content Security Policy (a `<meta>` tag, as Pages sets no headers) is `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'`: no scripts at all, styles and images from the site only. [`docs/.well-known/security.txt`](../../.well-known/security.txt) points to private vulnerability reporting.

## The checks

[`.github/scripts/site-check.py`](../../../.github/scripts/site-check.py) (workflow: [`site.yaml`](../../../.github/workflows/site.yaml); also run before every deploy) fails on:

- a page without exactly one CSP `<meta>`, or one that lacks the directives above, allows scripts or `unsafe-*`, or names another origin;
- any `<script>`, `<form>`, `<base>`, `<iframe>`, `<object>`, `<embed>` or inline `on…=` handler;
- anything that loads from another site (`<link>`, `<img>`, `src`, `srcset`), or a plain-`http` link;
- a local link or asset that does not exist (paths the apt repository adds at deploy time, such as `/pwsh-termux.gpg`, are allowed);
- a page without `lang`, a title, a viewport `<meta>`, exactly one `<h1>`, `<main id="main">`, a skip link, or an `alt` on an image;
- a `sitemap.xml` that does not list every page (except `404.html`), a `robots.txt` that does not point to it, a `CNAME` that is not the domain, or a `security.txt` with a wrong `Canonical` or an `Expires` less than 30 days away.

It uses only the standard library. The negative cases (an injected script, a missing file, a weakened CSP, a wrong `CNAME`) were tried by hand when it was written.

## Cache busting

Pages are cached for minutes and assets for hours, so at deploy time `assemble-site.sh` rewrites `"/style.css"` and `"/favicon.svg"` to `?v=<content hash>`. Nothing is stamped in the repository: the files in `docs/` stay plain.

## Search engines and AI assistants

Each page has Open Graph and Twitter card tags and a canonical link. [`robots.txt`](../../robots.txt) allows every crawler and points to [`sitemap.xml`](../../sitemap.xml), which lists the three pages (add a page there when you add one). [`llms.txt`](../../llms.txt) is a short, curated summary with links for AI assistants; keep its claims in step with the README and the install page. [`CITATION.cff`](../../../CITATION.cff) lets tools cite the project. The repository's description, homepage and topics are set in GitHub's settings.

## Updating `security.txt`

`Expires` is one year ahead when written. `site.yaml` runs weekly and fails when fewer than 30 days remain, as a reminder to extend it (RFC 9116 asks for an expiry).

## See also

- The live site: <https://pwsh-termux.machlev.org/>.
- How the site and the apt repository share one Pages deployment: [hosting](architecture/hosting.md).
- The CSP check and the workflows: [ci-cd.md](ci-cd.md).
