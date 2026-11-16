## What and why

<!-- Title: `type(scope): description` (see contributing.md). Link the issue: Fixes #123. -->

## Checklist

- [ ] Every commit is signed off (`git commit -s`), certifying the [Developer Certificate of Origin](https://developercertificate.org/) (see contributing.md)
- [ ] Changed a script? I ran it locally (see `docs/markDown/engineering/build.md`) and say what I ran above
- [ ] Changed `build-deb.sh`? I ran the package on a device (`build.md`, *Testing on a device*)
- [ ] Changed packaging, releases, the repository, keys or the site assembly? I ran the matching offline tests (`test-build-deb.sh`, `test-find-releases.sh`, `test-make-sboms.sh`, `test-assemble-site.sh`, `test-keys.sh`, `test-release-tags.sh`, `test-keepalive.sh`, `test-dco.sh`) and the keyring still builds byte-identical
- [ ] Changed behaviour or fixed a bug? I added a test (`scripts/test-*.sh` or `tests/fuzz`), or explain above why not
- [ ] Nothing is suppressed beyond `docs/markDown/engineering/exceptions.md`
- [ ] Added or changed an action? It is pinned to a commit SHA with its version in a comment
- [ ] Changed the website? Added a page to `docs/sitemap.xml`, kept the Content-Security-Policy (no scripts, inline `style`, forms or third-party loads)
- [ ] Changed the website? It meets the accessibility rules in `docs/markDown/engineering/website.md` (WCAG 2.2 AA) and the accessibility statement still holds
- [ ] Changed a diagram step? I updated `tools/diagrams/gen.mjs`, the GIFs, the Mermaid blocks and the `<ol>` lists together
- [ ] Docs updated where the change needs it

CI runs shellcheck, `site-check.py`, the HTML and CSS validation, Stylelint and the axe accessibility check; fix what it reports. The items above are the ones only you can check.
