// Screenshots of a running site (astro preview) for review: node scripts/shots.mjs URL OUTDIR
// Uses Playwright's Chromium, or the system one via PLAYWRIGHT_CHROMIUM (e.g. /usr/bin/chromium).
import { mkdirSync } from 'node:fs';
import { chromium } from '@playwright/test';

const [url = 'http://localhost:4321/omarchy-plugin-check/', out = 'shots'] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const browser = await chromium.launch(
  process.env.PLAYWRIGHT_CHROMIUM ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM } : {},
);
const shots = [
  ['index', '', 1440, 900, true],
  ['report-omamail', 'plugins/omamail/', 1440, 900, true],
  ['report-flights', 'plugins/io.github.letsfg.flights/', 1440, 900, false],
  ['report-baseline', 'plugins/07dcolem.appimages/', 1440, 900, false],
  ['providers', 'providers/', 1440, 900, true],
  ['about', 'about/', 1440, 900, false],
  ['api', 'api/', 1440, 900, false],
  ['phone-index', '', 390, 844, false],
  ['phone-report', 'plugins/omamail/', 390, 844, false],
  ['unlisted', 'plugins/not.a.listed.plugin/', 1440, 700, false],
];
for (const [name, path, width, height, full] of shots) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto(url + path, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: full });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  console.log(name, `horizontal overflow ${overflow}px`);
  await page.close();
}
await browser.close();
