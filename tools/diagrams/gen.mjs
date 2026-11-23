// Draws the animated diagrams of the README, INSTALL.md and the site (docs/img/).
// usage: node tools/diagrams/gen.mjs <outdir>, then copy the 640-wide .gif files to docs/img/ (README, INSTALL.md); the site shows the steps as HTML.
// needs: node, ffmpeg, rsvg-convert (librsvg) and the Roboto font known to fontconfig
//   (on Termux: FONTCONFIG_FILE=<conf that adds /system/fonts>; see docs/markDown/engineering/build.md).
// The steps below are the single source: copy the written <name>.mmd into the Mermaid
// <details> blocks (README.md, INSTALL.md, docs/index.html, docs/install.html) when they change.
// writes <name>.gif and <name>-still.png (640 wide),
// <name>@2x.gif and <name>-still@2x.png (1280 wide, site 2x), and <name>.mmd.
// Palette follows the site: the dark code tile (#1d1d1f), Apple's dark-mode grays and systemBlue.
import { writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
// A GIF cannot be paused, so it plays once and stays on its last frame, and the steps take under five seconds
// together (WCAG 2.2.2).
const STEP = 0.6;
const out = process.argv[2];
mkdirSync(out, { recursive: true });
const diagrams = {
  'release-pipeline': [
    ['Microsoft publishes', 'PowerShell 7 releases on GitHub'],
    ['Choose releases', 'highest stable, plus a newer preview'],
    ['Verify', 'SHA-256 must match hashes.sha256'],
    ['Patch and package', 'Termux glibc loader, build the .deb'],
    ['Sign', 'apt index signed with Ed25519'],
    ['Publish', 'GitHub Pages and release assets'],
    ['Your phone', 'pkg update, pkg upgrade'],
  ],
  'install-steps': [
    ['Enable glibc', 'pkg install glibc-repo'],
    ['Download the keyring', 'public key and apt source'],
    ['Install the keyring', 'dpkg -i keyring.deb'],
    ['Refresh', 'pkg update checks the signature'],
    ['Install', 'pkg install pwsh'],
    ['Run', 'pwsh'],
  ],
};
const C = {
  bg: '#1d1d1f', box: '#2c2c2e', edge: '#3a3a3c', off: '#48484a',
  blue: '#0a84ff', tint: '#1b3a5c', ink: '#f5f5f7', ink2: '#a1a1a6',
};
const W = 640, BH = 76, GAP = 36, TOP = 28, X = 36, BW = W - 2 * X;
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
function frame(steps, active) {
  const H = TOP * 2 + steps.length * BH + (steps.length - 1) * GAP;
  let s = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" font-family="Roboto">` +
    `<rect width="${W}" height="${H}" rx="24" fill="${C.bg}"/>`;
  steps.forEach(([t, sub], i) => {
    const y = TOP + i * (BH + GAP);
    const on = i === active, done = i < active || active === steps.length;
    if (i > 0) {
      const lit = i <= active || active === steps.length;
      const col = lit ? C.blue : C.off, x = W / 2, y1 = y - GAP + 6, y2 = y - 6;
      s += `<line x1="${x}" y1="${y1}" x2="${x}" y2="${y2 - 7}" stroke="${col}" stroke-width="3" stroke-linecap="round"/>` +
        `<path d="M${x - 7} ${y2 - 9}L${x} ${y2}L${x + 7} ${y2 - 9}" fill="none" stroke="${col}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`;
    }
    const stroke = on ? C.blue : done ? C.blue : C.edge;
    s += `<rect x="${X}" y="${y}" width="${BW}" height="${BH}" rx="18" fill="${on ? C.tint : C.box}" stroke="${stroke}" stroke-width="${on ? 3 : 1.5}"/>` +
      `<circle cx="${X + 40}" cy="${y + BH / 2}" r="17" fill="${on || done ? C.blue : C.off}"/>` +
      `<text x="${X + 40}" y="${y + BH / 2 + 7}" text-anchor="middle" font-size="19" font-weight="600" fill="${C.ink}">${i + 1}</text>` +
      `<text x="${X + 76}" y="${y + 33}" font-size="22" font-weight="600" fill="${C.ink}">${esc(t)}</text>` +
      `<text x="${X + 76}" y="${y + 58}" font-size="17" fill="${C.ink2}">${esc(sub)}</text>`;
  });
  return s + '</svg>';
}
const gif = (list, dest) => execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list,
  '-vf', 'split[a][b];[a]palettegen=max_colors=32:reserve_transparent=1:stats_mode=full[p];[b][p]paletteuse=dither=none:alpha_threshold=128',
  '-loop', '-1', dest]);
for (const [name, steps] of Object.entries(diagrams)) {
  for (const [scale, suffix] of [[1, ''], [2, '@2x']]) {
    const list = [];
    for (let a = 0; a <= steps.length; a++) {
      const f = `${out}/${name}${suffix}-${String(a).padStart(2, '0')}`;
      writeFileSync(f + '.svg', frame(steps, a));
      execFileSync('rsvg-convert', ['-z', String(scale), '-o', f + '.png', f + '.svg']);
      list.push(`file '${f}.png'\nduration ${a === steps.length ? 1 : STEP}`);
    }
    const last = `${out}/${name}${suffix}-${String(steps.length).padStart(2, '0')}.png`;
    writeFileSync(`${out}/${name}${suffix}.txt`, list.join('\n') + `\nfile '${last}'\n`);
    gif(`${out}/${name}${suffix}.txt`, `${out}/${name}${suffix}.gif`);
    copyFileSync(last, `${out}/${name}-still${suffix}.png`);
  }
  const ids = steps.map((_, i) => String.fromCharCode(65 + i));
  const nodes = steps.map(([t, sub], i) => `    ${ids[i]}["${t}<br/>${sub}"]`).join('\n');
  writeFileSync(`${out}/${name}.mmd`, `flowchart TD\n${nodes}\n    ${ids.join(' --> ')}\n`);
}
