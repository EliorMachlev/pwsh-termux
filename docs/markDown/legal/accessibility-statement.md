# Accessibility statement

*The date and commit of this page's last change come from Git, not from the page: see the [documents page](https://pwsh-termux.machlev.org/documents.html) or this file's history on GitHub.*

The pwsh-termux website (`pwsh-termux.machlev.org`) is meant to be usable by everyone, including people who use screen readers, keyboards, magnification or high-contrast settings. This statement covers the website. The packages have no user interface of their own: PowerShell is a command-line shell and uses your terminal.

## How the site is built

- **Plain, semantic HTML** with one `<h1>` per page, ordered headings, `<nav>`, `<main>` and `<footer>` landmarks, `lang="en"`, and a "Skip to content" link as the first focusable element. A check ([`site-check.py`](../../../.github/scripts/site-check.py)) fails the build when a page loses any of these, or an image has no `alt`.
- **No JavaScript.** Everything works without it; nothing moves or updates by itself.
- **Keyboard.** Every link and control is reachable and operable by keyboard, with a visible focus ring.
- **Colour and contrast.** A light and a dark palette follow your system setting (`prefers-color-scheme`); every text and background pair meets the WCAG AA contrast ratio of 4.5:1 in both palettes (the lowest, links on a card in the light palette, is 4.9:1; body text is above 15:1), and information is never conveyed by colour alone.
- **Zoom and layout.** Layout is responsive and uses relative units; text can be enlarged without loss of content, and tables and code blocks scroll sideways instead of breaking the page. Narrow-screen layout has not been tested on every device.
- **Motion.** There is no animation; `prefers-reduced-motion` is respected anyway.
- **Code samples** are plain text in `<pre>` blocks, which screen readers read as written.

## Conformance

The site is **designed to meet WCAG 2.2 level AA**. It has **not been formally audited** by a third party; the claims above are what the build verifies or what was checked by hand. No known part of the site fails them.

## Known limitations

- The Markdown documentation is rendered by GitHub, whose accessibility is GitHub's.
- The README's badges are images from a third-party service with short text alternatives.
- Terminal output of `pkg` and `pwsh` depends on your terminal and its screen reader support.

## Feedback

If something is hard to use, [open an issue](https://github.com/EliorMachlev/pwsh-termux/issues) describing the page and the problem (and your assistive technology if you can). I aim to reply within 7 days and to fix real barriers promptly.
