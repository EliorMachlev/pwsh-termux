# Diagram generator

`gen.mjs` draws the two animated diagrams (`release-pipeline`, `install-steps`) shown in the README, `INSTALL.md` and the website, and writes the matching Mermaid source. GitHub's mobile apps and the site's CSP (no scripts) cannot render Mermaid, so the pictures are GIFs.

1. Edit the steps at the top of `gen.mjs`.
2. Run `node tools/diagrams/gen.mjs "$PWD/out"` (an absolute output folder). It needs `node`, `ffmpeg`, `rsvg-convert` (librsvg) and the Roboto font.
3. Copy `<name>.gif`, `<name>@2x.gif`, `<name>-still.png` and `<name>-still@2x.png` to `docs/img/`.
4. Copy each `<name>.mmd` into the Mermaid `<details>` blocks of `README.md`, `INSTALL.md`, `docs/index.html` and `docs/install.html`, and fix the `alt` text and the `width`/`height` of the pictures if the size changed.

On Termux, `pkg install librsvg fontconfig ffmpeg`, and point fontconfig at Android's fonts with a file holding `<fontconfig><include ignore_missing="yes">$PREFIX/etc/fonts/fonts.conf</include><dir>/system/fonts</dir></fontconfig>`, passed as `FONTCONFIG_FILE`.

See [website.md](../../docs/markDown/engineering/website.md#diagrams).
