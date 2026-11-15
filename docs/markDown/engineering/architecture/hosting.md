# Hosting

Everything is static files on GitHub Pages at `https://pwsh-termux.machlev.org/`, deployed by [`update.yaml`](../../../../.github/workflows/update.yaml) (Settings → Pages → *Source: GitHub Actions*).

## What is deployed

[`scripts/assemble-site.sh`](../../../../scripts/assemble-site.sh) merges the website into the apt repository's output folder:

1. It copies everything in `docs/` except `docs/markDown/` (the handbook stays on GitHub).
2. It fills the pages' generated blocks from the repository being deployed and from `git log` ([website](../website.md#generated-blocks)).
3. It rewrites every `"/style.css"` and `"/favicon.svg"` in the pages to `?v=<first 12 hex digits of the file's SHA-256>`. Browsers may keep assets for hours but pages for minutes, so without this a deploy could pair a new page with an old stylesheet. The files in `docs/` stay plain.

The artifact is uploaded with `include-hidden-files: true`; otherwise `actions/upload-pages-artifact` drops every dotfile, including `.well-known/security.txt` (it still excludes `.git` and `.github`).

## Release assets

Each new `pwsh` or `pwsh-preview` `.deb` is also published once as a GitHub release, tagged `<package>-<version>` (`~` becomes `-`), so the site stays stateless and older builds stay downloadable. `pwsh-preview` releases are prereleases.

## The custom domain

`docs/CNAME` holds `pwsh-termux.machlev.org`; for a workflow-deployed site it is informational. The domain is set in the Pages settings (or `gh api -X PUT repos/EliorMachlev/pwsh-termux/pages -f cname=pwsh-termux.machlev.org`) and needs a DNS record `CNAME pwsh-termux → eliormachlev.github.io`. With *Enforce HTTPS* on, `https://eliormachlev.github.io/pwsh-termux/` redirects to the domain, which apt follows. Full checklist: [release](../release.md#custom-domain).

## Concurrency and failure

The `concurrency: pages` group serialises deploys and never cancels one half way. A failed run leaves the previous deployment in place; nothing partial is published.

## Limits

GitHub Pages allows a 1 GB site and a soft 100 GB/month of bandwidth. The site holds two `.deb` files of about 50 MB each; release assets do not count.
