## What and why

<!-- Title: `type(scope): description` (see contributing.md). Link the issue: Fixes #123. -->

## Checklist

- [ ] `shellcheck --shell=bash --severity=style scripts/*.sh` is clean
- [ ] `python3 .github/scripts/site-check.py docs` passes
- [ ] Changed a script? I ran it locally (see `docs/markDown/engineering/build.md`) and say what I ran above
- [ ] Nothing is suppressed beyond `docs/markDown/engineering/exceptions.md`
- [ ] Added or changed an action? It is pinned to a commit SHA with its version in a comment
- [ ] Changed the website? Added a page to `docs/sitemap.xml` and kept the Content-Security-Policy
- [ ] Docs updated where the change needs it
