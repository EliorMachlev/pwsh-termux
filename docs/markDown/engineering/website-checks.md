# Website checks

The checks that keep the [website](website.md) script-free, valid and consistent. Run them locally as [build](build.md#check-the-website) shows.

## site-check.py

[`.github/scripts/site-check.py`](../../../.github/scripts/site-check.py) (standard library only) fails on:

1. a page without exactly one CSP `<meta>`, or one that lacks `default-src 'none'`, `base-uri 'none'` or `form-action 'none'`, allows scripts or `unsafe-*`, or contains `http:`, `https:` or `*` (a bare host name is not caught);
2. any `<script>`, `<form>`, `<base>`, `<iframe>`, `<object>`, `<embed>` or inline `on…=` handler;
3. anything loaded from another site (`<link>`, `<img>`, `src`, `srcset`), or a plain-`http` link;
4. a missing local link or asset (paths the apt repository adds at deploy time, such as `/pwsh-termux.gpg`, are allowed), or a missing `style.css`, `favicon.svg`, `llms.txt` or `.nojekyll`;
5. a generated block not opened and closed in order;
6. a page without `lang`, a title, a viewport `<meta>`, exactly one `<h1>`, `<main id="main">`, a skip link, or an `alt` on each image;
7. a `sitemap.xml` that does not list every page but `404.html`, a `robots.txt` that does not point to it, a `CNAME` that is not the domain, or a `security.txt` with a wrong `Canonical` or fewer than 30 days before `Expires`.

It runs on `docs/` in [`site.yaml`](../../../.github/workflows/site.yaml) and before every deploy, and on the assembled site (generated blocks filled) in CI's package build, `update.yaml` and `recover.yaml`.

## Valid HTML and CSS

`site.yaml`'s *Validate the HTML and CSS* job, a required check on every pull request, fails on any message; nothing is filtered.

1. **W3C Nu Html Checker** (vnu, the checker behind [validator.w3.org/nu](https://validator.w3.org/nu/)), through [`scripts/validate-site.sh`](../../../scripts/validate-site.sh), with `--Werror --also-check-css --also-check-svg`, on three folders:
   1. `docs/` as committed;
   2. the site as deployed, assembled by `build-repo.sh` (unsigned) and `assemble-site.sh` around a stand-in `pwsh` package, so generated blocks are checked filled;
   3. `art/brand/`.

   Errors, warnings and info messages all fail; no `--filterfile`, `--filterpattern` or `--skip-info-messages`. Pages are served from `127.0.0.1`, not opened as `file:` URLs, so the CSP's `'self'` is the site's origin as in a browser; `nu.validator.servlet.allow-forbidden-hosts` lets vnu fetch from loopback and changes nothing it reports. [`test-validate-site.sh`](../../../scripts/test-validate-site.sh) tests the script on fixture sites first.
2. **Stylelint** with [`stylelint-config-standard`](https://github.com/stylelint/stylelint-config-standard), unchanged ([`.stylelintrc.json`](../../../tools/site-lint/.stylelintrc.json) only extends it), on `docs/style.css` and the deployed copy, with `--max-warnings 0` and `--ignore-disables`, so a `stylelint-disable` comment hides nothing.

## Tool pinning

Both are pinned in [`tools/site-lint/`](../../../tools/site-lint): exact versions in `package.json`, integrity hashes in `package-lock.json`; Dependabot updates them ([ci-cd.md](ci-cd.md#dependabot)).

1. vnu comes from `vnu-jar`, the validator project's own npm release of `vnu.jar`, with a provenance attestation that `npm audit signatures` checks (its GitHub releases offer only a rolling `latest`). It runs on the runner's Java (17 or later).
2. `npm ci --ignore-scripts` installs the tools; nothing from them reaches `docs/`, and the site still has no JavaScript.
