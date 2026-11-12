# Hosting

Everything is static files on **GitHub Pages**, deployed by a workflow (Settings → Pages → *Source: GitHub Actions*), at `https://pwsh-termux.machlev.org/`.

## What is deployed

[`scripts/assemble-site.sh`](../../../../scripts/assemble-site.sh) merges the website into the apt repository's output folder:

- everything in `docs/` **except** `docs/markDown/` (the handbook lives on GitHub, not on the site);
- the generated blocks in the pages are filled from the repository being deployed: `status`, the versions in `Packages` and the `Date` and `Valid-Until` of `Release`; `documents` and `last-updated:<path>`, each Markdown document's last commit date and short SHA from `git log`, which needs the checkout's full history ([website](../website.md));
- every `"/style.css"` and `"/favicon.svg"` reference in the pages is rewritten to `?v=<12 hex digits of the file's SHA-256>`. Pages and the CDN let browsers keep a stylesheet for hours but a page for minutes, so without this a deploy could pair a new page with an old stylesheet.

The artifact is uploaded with `include-hidden-files: true`. Without it `actions/upload-pages-artifact` skips every dotfile and would silently drop `.well-known/security.txt` (it still excludes `.git` and `.github`).

## Release assets

Each built `.deb` is also published as a GitHub release (`<package>-<version>`, `~` replaced by `-`) the first time it appears, so the Pages site can stay stateless and older builds stay downloadable. `pwsh-preview` releases are marked as prereleases.

## The custom domain

`docs/CNAME` contains `pwsh-termux.machlev.org`. For a workflow-deployed site the file is informational: the domain is set in the repository's Pages settings (or with `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -f cname=pwsh-termux.machlev.org`). It needs a DNS record at the domain's DNS provider:

| Type | Name | Target |
|---|---|---|
| `CNAME` | `pwsh-termux` | `eliormachlev.github.io` |

Once GitHub has issued the certificate, *Enforce HTTPS* can be switched on. After that, `https://eliormachlev.github.io/pwsh-termux/` redirects to the custom domain, which apt follows. [Release](../release.md#custom-domain) has the full checklist, including domain verification.

## Concurrency and failure

The workflow's `concurrency: pages` group serialises deploys and never cancels one half way. A failed run leaves the previous deployment in place; nothing partial is published.

## Limits

GitHub Pages has size and bandwidth limits (a 1 GB site and a soft 100 GB/month). The site holds two `.deb` files of about 50 MB, which is well inside them; the release archive is not subject to them.
