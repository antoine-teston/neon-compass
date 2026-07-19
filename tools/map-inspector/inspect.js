// Map inspector — loads a Leaflet-based map in a real browser and reports where
// its base imagery (tiles) and data actually come from. Read-only observation:
// we do NOT download or persist third-party map content, only classify request
// origins so we can reason about IP/licensing. See CLAUDE.md "IP" constraints.

import { chromium } from 'playwright';

const TARGET = process.argv[2] ?? 'https://map.stateofleonida.net/';
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

const requests = [];

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ userAgent: UA, viewport: { width: 1440, height: 900 } });
const page = await ctx.newPage();

page.on('request', (r) => {
  requests.push({ url: r.url(), type: r.resourceType(), method: r.method() });
});

console.log(`→ loading ${TARGET}`);
await page.goto(TARGET, { waitUntil: 'networkidle', timeout: 60000 }).catch((e) => {
  console.log('goto note:', e.message);
});
// give Leaflet time to request tiles after the map initializes
await page.waitForTimeout(6000);

// Classify tile-ish requests (image tiles usually match /{z}/{x}/{y} or a tiles path)
const isTile = (u) =>
  /\/\d+\/\d+\/\d+\.(png|jpg|jpeg|webp)/i.test(u) || /tiles?\//i.test(u);

const tiles = requests.filter((r) => (r.type === 'image' || isTile(r.url)) && isTile(r.url));
const byHost = {};
for (const r of requests) {
  const host = new URL(r.url).host;
  byHost[host] = (byHost[host] || 0) + 1;
}

console.log('\n=== Hosts contacted (request count) ===');
for (const [h, n] of Object.entries(byHost).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${n.toString().padStart(4)}  ${h}`);
}

console.log('\n=== Sample base-map / tile requests ===');
const seen = new Set();
let shown = 0;
for (const r of tiles) {
  const key = r.url.replace(/\d+\/\d+\/\d+/, '{z}/{x}/{y}');
  if (seen.has(key)) continue;
  seen.add(key);
  console.log(`  ${r.url}`);
  if (++shown >= 20) break;
}
if (shown === 0) console.log('  (no tile-pattern requests captured)');

// Screenshot of the rendered base map for visual inspection
await page.screenshot({ path: 'map-render.png', fullPage: false });
console.log('\n→ saved screenshot: map-render.png');

await browser.close();
