// Accessibility check of the website (site.yaml, job "accessibility"): axe-core in headless Chrome against
// every page, in light and dark, with and without reduced motion, at desktop and phone width.
// usage: node tools/site-lint/axe-check.mjs <site-folder>   (CHROME_BIN names the browser; default google-chrome)
// Fails on any axe violation of WCAG 2.0 to 2.2 level A and AA, on horizontal scrolling at 320 px (reflow,
// 1.4.10), and on a diagram whose pause checkbox is missing. CI tooling only: nothing here ships on the site.
import { createServer } from 'node:http';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { createRequire } from 'node:module';
import puppeteer from 'puppeteer-core';

const require = createRequire(import.meta.url);
const axeSource = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');
const root = resolve(process.argv[2] ?? 'docs');
const types = { '.html': 'text/html', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.gif': 'image/gif' };
const pages = readdirSync(root).filter(f => f.endsWith('.html'));

// Served from 127.0.0.1, not opened as file:, so the pages' CSP ('self') is the site's origin as in a browser.
const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  const file = join(root, path === '/' ? 'index.html' : path);
  if (!file.startsWith(root + '/') || !existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file));
}).listen(0, '127.0.0.1');
await new Promise(r => server.once('listening', r));
const base = `http://127.0.0.1:${server.address().port}`;

const browser = await puppeteer.launch({
  executablePath: process.env.CHROME_BIN ?? '/usr/bin/google-chrome',
  args: ['--no-sandbox'],
  headless: true,
});
const problems = [];
const modes = [
  { scheme: 'light', motion: 'no-preference', width: 1280 },
  { scheme: 'dark', motion: 'no-preference', width: 1280 },
  { scheme: 'light', motion: 'reduce', width: 390 },
  { scheme: 'dark', motion: 'reduce', width: 320 },
];
for (const page of pages) {
  for (const m of modes) {
    const tab = await browser.newPage();
    const label = `${page} (${m.scheme}, motion ${m.motion}, ${m.width}px)`;
    await tab.setViewport({ width: m.width, height: 900 });
    await tab.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: m.scheme },
      { name: 'prefers-reduced-motion', value: m.motion },
    ]);
    await tab.goto(`${base}/${page}`, { waitUntil: 'networkidle0' });
    // The diagrams animate for several seconds: pause them so colours are measured at rest, not mid-fade.
    await tab.evaluate(() => document.querySelectorAll('.flow input').forEach(i => i.click()));
    await tab.evaluate(axeSource);
    const result = await tab.evaluate(() => axe.run(document, {
      runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'] },
    }));
    for (const v of result.violations) {
      for (const n of v.nodes) problems.push(`${label}: ${v.id}: ${v.help}: ${n.target.join(' ')}`);
    }
    if (m.width === 320 && await tab.evaluate(() => document.documentElement.scrollWidth > innerWidth)) {
      problems.push(`${label}: scrolls sideways (WCAG 1.4.10)`);
    }
    const flows = await tab.evaluate(() => document.querySelectorAll('.flow').length);
    const pauses = await tab.evaluate(() => document.querySelectorAll('.flow input[type=checkbox]').length);
    if (flows !== pauses) problems.push(`${label}: a .flow list has no pause checkbox (WCAG 2.2.2)`);
    await tab.close();
  }
}
await browser.close();
server.close();
if (problems.length) {
  console.error([...new Set(problems)].join('\n'));
  process.exit(1);
}
console.log(`Accessibility check passed: ${pages.length} pages x ${modes.length} modes, WCAG 2.2 A and AA.`);
