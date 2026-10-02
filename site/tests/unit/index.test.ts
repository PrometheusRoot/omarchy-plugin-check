import { describe, expect, it } from 'vitest';
import { decodeIndex, encodeIndex, type IndexRow } from '../../src/lib/compact';
import { DEFAULT_QUERY, fromParams, PAGE_SIZE, type Query, run, toParams } from '../../src/lib/query';
import { esc, rowHtml } from '../../src/lib/render';
import { fixtureDocs, fixtureMeta } from './helpers';

const meta = fixtureMeta();
const docs = fixtureDocs();
const idx = encodeIndex(docs, meta, meta.providers);
const rows = decodeIndex(idx);
const byId = (id: string) => rows.find((r) => r.id === id) as IndexRow;
const q = (p: Partial<Query>) => run(rows, { ...DEFAULT_QUERY, ...p });

describe('compact index', () => {
  it('round-trips every plugin with its verdict, listing state and providers', () => {
    expect(rows).toHaveLength(docs.length);
    for (const d of docs) {
      const r = byId(d.id);
      expect(r.verdict).toBe(d.combined.verdict);
      expect(r.listing).toBe(d.listingState);
      expect(r.providers.map((p) => p.id).sort()).toEqual(d.providers.map((p) => p.provider).sort());
    }
  });
  it('carries review facts only for reviewed plugins', () => {
    const om = byId('omamail');
    expect(om.commit).toHaveLength(7);
    expect(om.caps.map((c) => c.key)).toContain('network');
    expect(om.hosts).toContain('gmail.googleapis.com');
    expect(om.risk).toBe(13);
    const plain = byId('omaplug');
    expect(plain.commit).toBe('');
    expect(plain.caps).toEqual([]);
  });
  it('keeps the marketplace cap and contested flag', () => {
    expect(byId('fixture.contested-widget').contested).toBe(true);
    const mkt = byId('omamail').providers.find((p) => p.id === 'marketplace');
    expect(mkt?.tier).toBe('unsigned');
  });
  it('stays compact (bytes per plugin)', () => {
    expect(JSON.stringify(idx).length / docs.length).toBeLessThan(400);
  });
});

describe('query', () => {
  it('searches name, id, repo and hosts with all terms', () => {
    expect(q({ q: 'omamail' }).rows[0]?.id).toBe('omamail');
    expect(q({ q: 'gmail.googleapis' }).rows.map((r) => r.id)).toEqual(expect.arrayContaining(['omamail']));
    expect(q({ q: 'omamail zzzz' }).total).toBe(0);
  });
  it('filters by state and counts states over the other filters', () => {
    const res = q({ state: 'blocked' });
    expect(res.rows.map((r) => r.id)).toEqual(['fixture.blocked-widget']);
    expect(res.counts.all).toBe(rows.length);
    expect(res.counts.retired).toBe(1);
    expect(q({ reviewedOnly: true }).rows.every((r) => r.commit !== '')).toBe(true);
  });
  it('sorts worst first and by risk', () => {
    expect(q({ sort: 'verdict', dir: 'desc' }).rows[0]?.id).toBe('fixture.blocked-widget');
    const risk = q({ sort: 'risk', dir: 'desc' }).rows.map((r) => r.risk ?? -1);
    expect(risk).toEqual([...risk].sort((a, b) => b - a));
  });
  it('paginates and clamps the page', () => {
    const many = Array.from(
      { length: 130 },
      (_, i) => ({ ...rows[0], id: `p${i}`, rank: i + 1 }) as IndexRow,
    );
    const res = run(many, { ...DEFAULT_QUERY, page: 99 });
    expect(res.pages).toBe(Math.ceil(130 / PAGE_SIZE));
    expect(res.page).toBe(res.pages);
    expect(res.rows).toHaveLength(130 - (res.pages - 1) * PAGE_SIZE);
  });
  it('runs a keystroke over ~4.8k rows quickly', () => {
    const big = Array.from(
      { length: 4800 },
      (_, i) => ({ ...rows[i % rows.length], id: `x${i}` }) as IndexRow,
    );
    const t = performance.now();
    for (let i = 0; i < 20; i++) run(big, { ...DEFAULT_QUERY, q: 'om', sort: 'stars', dir: 'desc' });
    expect((performance.now() - t) / 20).toBeLessThan(16);
  });
  it('round-trips through URL params and omits defaults', () => {
    expect(toParams(DEFAULT_QUERY).toString()).toBe('');
    const query: Query = {
      ...DEFAULT_QUERY,
      q: 'mail',
      state: 'caution',
      sort: 'stars',
      dir: 'asc',
      page: 3,
    };
    expect(fromParams(toParams(query))).toEqual(query);
    expect(fromParams(new URLSearchParams('v=bogus&sort=nope&page=-2'))).toEqual(DEFAULT_QUERY);
  });
});

describe('row html', () => {
  it('escapes everything it interpolates', () => {
    expect(esc('<a href="x">&\'')).toBe('&lt;a href=&quot;x&quot;&gt;&amp;&#39;');
    const evil = { ...byId('omaplug'), name: '<img src=x onerror=alert(1)>' };
    expect(rowHtml('/b/', evil)).not.toContain('<img');
  });
  it('links the report under the base path and the marketplace listing', () => {
    const html = rowHtml('/omarchy-plugin-check/', byId('omamail'));
    expect(html).toContain('href="/omarchy-plugin-check/plugins/omamail/"');
    expect(html).toContain('https://plugins.omarchy.org/plugin.html?id=omamail');
    expect(html).toContain('class="glyph c-caution');
  });
});
