# Accessibility statement

*This page's last change (date and commit) comes from Git: see the [documents page](https://pwsh-termux.machlev.org/documents.html) or this file's history on GitHub.*

The pwsh-termux website (`pwsh-termux.machlev.org`) is meant to be usable by everyone, including people using screen readers, keyboards, magnification or high-contrast settings. This statement covers the website; the packages have no interface of their own (PowerShell is a command-line shell in your terminal).

## How the site is built

- **Semantic HTML:** one `<h1>` per page, ordered headings, `<nav>`, `<main>` and `<footer>` landmarks, `lang="en"`, and a "Skip to content" link as the first focusable element. [`site-check.py`](../../../.github/scripts/site-check.py) fails the build if a page loses its `lang`, its single `<h1>`, its `<main>` or its skip link, or if an image has no `alt`; heading order, the `<nav>` and `<footer>` landmarks and the skip link's position are checked by hand.
- **No JavaScript.** Everything works without it; nothing moves or updates by itself.
- **Keyboard:** every link and control is reachable and operable by keyboard, with a visible focus ring.
- **Colour and contrast:** light and dark palettes follow your system (`prefers-color-scheme`). Every text and background pair meets WCAG AA (4.5:1) in both; the lowest, links on a card in the light palette, is 4.9:1, and body text is above 15:1. Links inside a sentence are underlined, and information is never conveyed by colour alone.
- **Zoom and layout:** responsive, in relative units; text can be enlarged without loss of content, and tables and code blocks wrap instead of scrolling sideways or breaking the page. Narrow-screen layout has not been tested on every device.
- **Motion:** nothing moves by itself. The two diagrams show as still pictures; an animated version opens only when you choose *Play the animation*. `prefers-reduced-motion` is respected anyway.
- **Code samples** are plain text in `<pre>` blocks, read by screen readers as written.

## Conformance

The site is **designed to meet WCAG 2.2 level AA**. It has **not been formally audited** by a third party; the claims above are verified by the build or checked by hand. No known part of the site fails them.

## Known limitations

- The Markdown documentation is rendered by GitHub; its accessibility is GitHub's.
- The README's badges are third-party images with short text alternatives.
- Terminal output of `pkg` and `pwsh` depends on your terminal and its screen reader support.

## Feedback

If something is hard to use, [open an issue](https://github.com/EliorMachlev/pwsh-termux/issues) naming the page and the problem (and your assistive technology if you can). I aim to reply within 7 days and to fix real barriers promptly.
