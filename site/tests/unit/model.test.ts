import { describe, expect, it } from 'vitest';
import {
  activitySeries,
  areaHits,
  capHits,
  combinedNote,
  commitView,
  countsAs,
  criteriaView,
  pluginState,
  primaryReportRow,
  publicReason,
  sortRows,
  sparkPoints,
  splitFindings,
  stateRank,
} from '../../src/lib/model';
import type { ProviderRow } from '../../src/lib/types';
import { doc } from './helpers';

const row = (p: Partial<ProviderRow>): ProviderRow => ({
  provider: 'x',
  tier: 'core',
  verification: 'sigstore',
  commit: 'a'.repeat(40),
  verdict: 'safe',
  effectiveVerdict: 'safe',
  adjustments: [],
  counted: true,
  timeReviewed: '2026-10-01T00:00:00Z',
  ...p,
});

describe('states', () => {
  it('retired replaces the verdict; unknown reads as unreviewed', () => {
    expect(pluginState('retired', 'blocked')).toBe('retired');
    expect(pluginState('listed', 'unknown')).toBe('unreviewed');
    expect(pluginState('builtin', 'caution')).toBe('caution');
  });
  it('ranks blocked worst and listing states lowest', () => {
    expect(stateRank('blocked')).toBeGreaterThan(stateRank('risky'));
    expect(stateRank('risky')).toBeGreaterThan(stateRank('caution'));
    expect(stateRank('unreviewed')).toBeGreaterThan(stateRank('retired'));
  });
});

describe('provider rows', () => {
  it('sorts core, verified, community, unsigned, then by id', () => {
    const rows = [
      row({ provider: 'mkt', tier: 'unsigned' }),
      row({ provider: 'b', tier: 'verified' }),
      row({ provider: 'z', tier: 'core' }),
      row({ provider: 'a', tier: 'verified' }),
    ];
    expect(sortRows(rows).map((r) => r.provider)).toEqual(['z', 'a', 'b', 'mkt']);
  });
  it('shows capped rows as ≤ and uncounted rows as not counted', () => {
    expect(countsAs(row({ tier: 'unsigned', effectiveVerdict: 'caution' }))).toEqual({
      state: 'caution',
      capped: true,
    });
    expect(countsAs(row({ counted: false })).state).toBeNull();
  });
  it('picks the trusted report row as primary', () => {
    const d = doc('omamail');
    expect(primaryReportRow(d.providers)?.provider).toBe('opc');
    expect(primaryReportRow(doc('omaplug').providers)).toBeNull();
  });
});

describe('criteria', () => {
  it('maps every vocabulary criterion to pass / fail / na', () => {
    const v = criteriaView({ checked: ['no-exec', 'no-network'], failed: ['no-network'] });
    expect(v).toHaveLength(8);
    expect(v.find((c) => c.id === 'no-exec')?.state).toBe('pass');
    expect(v.find((c) => c.id === 'no-network')?.state).toBe('fail');
    expect(v.find((c) => c.id === 'reviewed-by-human')?.state).toBe('na');
    expect(criteriaView(undefined).every((c) => c.state === 'na')).toBe(true);
  });
});

describe('report helpers', () => {
  const d = doc('omamail');
  const opc = d.providers.find((r) => r.provider === 'opc');
  const report = opc?.detail?.report;
  it('lists capabilities above none in vocabulary order', () => {
    expect(capHits(report?.capabilities).map((c) => c.key)).toEqual(['processExec', 'network', 'fileWrite']);
    expect(capHits(undefined)).toEqual([]);
    expect(areaHits(report)).toEqual([]);
  });
  it('compares the reviewed commit with upstream and the marketplace', () => {
    if (!opc) throw new Error('fixture lacks opc row');
    const cv = commitView(opc, d.providers);
    expect(cv?.reviewed).toBe(opc.commit);
    expect(cv?.moved).toBe(true);
    expect(cv?.marketplaceMatch).toBe(true);
    expect(commitView(row({ commit: null }), [])).toBeNull();
  });
  it('never shows opaque rule ids (anti-oracle)', () => {
    expect(publicReason('r.0123456789ab')).toBe('');
    expect(publicReason('zizmor.unpinned-uses; r.abcdef012345, zizmor.cache-poisoning')).toBe(
      'zizmor.unpinned-uses · zizmor.cache-poisoning',
    );
  });
  it('splits findings worst first, info last', () => {
    const { notable, info } = splitFindings(report?.findings ?? []);
    expect(notable.length).toBe(4);
    expect(info.every((f) => f.severity === 'info')).toBe(true);
    expect(notable.length + info.length).toBe(report?.findings.length);
  });
  it('builds a sparkline only from known weeks', () => {
    expect(activitySeries(undefined)).toBeNull();
    expect(activitySeries([null, null])).toBeNull();
    expect(activitySeries([null, 2, 4])).toEqual([0, 2, 4]);
    const pts = sparkPoints([0, 10], 100, 20);
    expect(pts[0]).toEqual([4, 16]);
    expect(pts[1]).toEqual([96, 8]);
  });
  it('explains the combined verdict', () => {
    expect(combinedNote(d)).toMatch(/worst of core \+ verified/);
    expect(combinedNote(doc('fixture.retired-widget'))).toMatch(/retired/);
    expect(combinedNote(doc('omaplug'))).toMatch(/no trusted review|no provider/);
  });
});
