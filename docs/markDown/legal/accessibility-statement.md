# Accessibility statement

*This page's last change (date and commit) comes from Git: see the [documents page](https://pwsh-termux.machlev.org/documents.html) or this file's history on GitHub.*

The pwsh-termux website (`pwsh-termux.machlev.org`) is meant to be usable by everyone, including people using screen readers, keyboards, magnification or high-contrast settings. This statement covers the website; the packages have no interface of their own (PowerShell is a command-line shell in your terminal).

## How the site is built

- **Semantic HTML:** one `<h1>` per page, ordered headings, `<nav>`, `<main>` and `<footer>` landmarks, `lang="en"`, and a "Skip to content" link as the first focusable element. [`site-check.py`](../../../.github/scripts/site-check.py) fails the build if a page loses its `lang`, its single `<h1>`, its `<main>` or its skip link, if an image has no `alt`, if a heading level is skipped, if a page of 300 words or more has no summary paragraph (`class="lead"`), or if apt, DNS, Ed25519, SHA-256, SBOM or glibc is not explained at its first use on a page; the `<nav>` and `<footer>` landmarks and the skip link's position are checked by hand.
- **No JavaScript.** Everything works without it; nothing moves or updates by itself.
- **Keyboard:** every link and control is reachable and operable by keyboard, with a visible focus ring in the text colour (at least 10:1 against the page, tiles and chips, and at least 3:1 beside a filled button).
- **Colour and contrast:** light and dark palettes follow your system (`prefers-color-scheme`). Every text and background pair meets WCAG AA (4.5:1) in both; the lowest, a link on the status chip in the light palette, is 5.8:1, and body text is above 15:1. Muted text and links reach APCA lightness contrast Lc 75 or more on the page and tiles in both palettes (Lc 71 to 76 on the status chip), the figure the WCAG 3 draft is expected to use; WCAG 3 is a draft and WCAG 2.2 stays the standard. Links inside a sentence are underlined, and information is never conveyed by colour alone.
- **Zoom and layout:** responsive, in relative units; text can be enlarged without loss of content, and tables and code blocks wrap instead of scrolling sideways or breaking the page. Narrow-screen layout has not been tested on every device.
- **Motion:** the steps of the two diagrams light up in turn once, in about four seconds, then stay lit. A checkbox pauses them, and with `prefers-reduced-motion` they show finished and the checkbox is hidden. Nothing else moves.
- **Dates and terms:** dates are written out (2 January 2026) with the machine-readable form in `<time datetime>`, and the abbreviations a page uses are explained where they first appear.
- **Code samples** are plain text in `<pre>` blocks, read by screen readers as written.

## Conformance

The site is **designed to meet WCAG 2.2 level AA**. It has **not been formally audited** by a third party; the claims above are verified by the build or checked by hand. No known part of the site fails them.

## Known limitations

- The Markdown documentation is rendered by GitHub; its accessibility is GitHub's.
- The README's badges are third-party images with short text alternatives. The README's and `INSTALL.md`'s diagrams are animated GIFs that play once, in about four seconds, and stay on the last frame; the site shows the same steps as text.
- A pass with TalkBack, a keyboard-only pass, 200% text and WCAG text-spacing overrides on a phone is [still to do](https://github.com/EliorMachlev/pwsh-termux/issues/60); axe covers what a script can.
- Terminal output of `pkg` and `pwsh` depends on your terminal and its screen reader support.

## Feedback

If something is hard to use, [open an issue](https://github.com/EliorMachlev/pwsh-termux/issues) naming the page and the problem (and your assistive technology if you can). I aim to reply within 7 days and to fix real barriers promptly.
