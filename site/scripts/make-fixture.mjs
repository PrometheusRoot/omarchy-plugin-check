// Regenerate the committed test fixture (tests/fixtures/api/v1) from a snapshot build:
//   node scripts/make-fixture.mjs <snapshot>/api/v1 [providers.json]
// Picks real plugins (three with embedded reports, a few baseline-only, a built-in, one without
// provider rows) and derives three synthetic states the dev snapshot lacks: retired, blocked with
// evidence, and contested. Synthetic ids live under `fixture.` so they never collide with listings.
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [src, registry] = process.argv.slice(2);
if (!src) throw new Error('usage: make-fixture.mjs <api/v1 dir> [providers.json]');
const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', 'tests', 'fixtures', 'api', 'v1');
rmSync(out, { recursive: true, force: true });
mkdirSync(join(out, 'plugins'), { recursive: true });

const read = (p) => JSON.parse(readFileSync(p, 'utf8'));
const REAL = [
  'omamail',
  'akitaonrails.ai-usagebar',
  'tornikegomareli.spaces',
  'io.github.sirjul1337.lock-explorer',
  'crmne.hyprmoncfg',
  'omaplug',
  'omarchy.battery',
  'aislandener.clickup',
];
const docs = REAL.map((id) => read(join(src, 'plugins', `${id}.json`)));
for (const d of docs) {
  for (const r of d.providers) {
    if (r.statement) {
      mkdirSync(join(out, dirname(r.statement)), { recursive: true });
      copyFileSync(join(src, r.statement), join(out, r.statement));
    }
  }
}

const clone = (o) => JSON.parse(JSON.stringify(o));
const derive = (from, id, name, patch) => {
  const d = clone(from);
  d.id = id;
  d.name = name;
  d.marketplaceUrl = `https://plugins.omarchy.org/plugin.html?id=${id}`;
  if (d.listing) {
    d.listing.id = id;
    d.listing.name = name;
    d.listing.rank = (d.listing.rank ?? 0) + 1000;
  }
  for (const r of d.providers) r.statement = null;
  patch(d);
  return d;
};
const omamail = docs[0];
const opcRow = (d) => d.providers.find((r) => r.provider === 'opc');

docs.push(
  derive(docs[2], 'fixture.retired-widget', 'Retired Widget', (d) => {
    d.listingState = 'retired';
    d.combined = { verdict: 'unknown', basis: 'none', contested: false, commits: [], reasons: ['retired'] };
    if (d.listing) d.listing.state = 'retired';
  }),
  derive(omamail, 'fixture.blocked-widget', 'Blocked Widget', (d) => {
    const r = opcRow(d);
    r.verdict = 'blocked';
    r.effectiveVerdict = 'blocked';
    const rep = r.detail.report;
    rep.verdict.outcome = 'blocked';
    rep.verdict.score = 100;
    const f = rep.findings.find((x) => x.severity !== 'info');
    f.severity = 'critical';
    f.hardFail = true;
    f.category = 'exec';
    f.message = 'Process runs a script fetched over the network (curl | bash).';
    rep.verdict.hardFails = [f.id];
    d.combined = { ...d.combined, verdict: 'blocked', reasons: ['opc [core]: blocked'] };
    if (d.listing?.verdict) d.listing.verdict = { ...d.listing.verdict, combined: 'blocked', risk: 100 };
  }),
  derive(omamail, 'fixture.contested-widget', 'Contested Widget', (d) => {
    const r = clone(opcRow(d));
    r.provider = 'example';
    r.tier = 'verified';
    r.verdict = 'safe';
    r.effectiveVerdict = 'safe';
    r.detail = { scope: { kind: 'full', path: '' }, method: ['static'], target: 'marketplace-listing' };
    d.providers.push(r);
    const opc = opcRow(d);
    opc.verdict = 'risky';
    opc.effectiveVerdict = 'risky';
    opc.detail.report.verdict.outcome = 'risky';
    d.combined = { ...d.combined, verdict: 'risky', contested: true };
    if (d.listing?.verdict) d.listing.verdict = { ...d.listing.verdict, combined: 'risky', contested: true };
  }),
);

for (const d of docs) writeFileSync(join(out, 'plugins', `${d.id}.json`), `${JSON.stringify(d)}\n`);
const meta = read(join(src, 'meta.json'));
const counts = { safe: 0, caution: 0, risky: 0, blocked: 0, unknown: 0 };
for (const d of docs) counts[d.combined.verdict] += 1;
meta.providers.push({
  id: 'example',
  name: 'Example verified provider (fixture)',
  tier: 'verified',
  verification: 'sigstore',
  feedVersion: 1,
  feedExpires: meta.registry.expires,
  rows: 1,
  status: 'ok',
});
writeFileSync(
  join(out, 'meta.json'),
  `${JSON.stringify({ ...meta, pluginCount: docs.filter((d) => d.providers.length).length, counts })}\n`,
);
const index = read(join(src, 'index.json'));
writeFileSync(
  join(out, 'index.json'),
  `${JSON.stringify({ ...index, plugins: index.plugins.filter((p) => REAL.includes(p.id)) })}\n`,
);
const repos = {};
for (const d of docs) {
  const key = d.repo.replace('https://github.com/', '').toLowerCase();
  repos[key] = [...(repos[key] ?? []), d.id];
}
writeFileSync(
  join(out, 'by-repo.json'),
  `${JSON.stringify({ schemaVersion: 1, generatedAt: index.generatedAt, repos })}\n`,
);
if (registry && existsSync(registry)) cpSync(registry, join(out, '..', '..', 'providers.json'));
console.log(`fixture: ${docs.length} plugins → ${out}`);
