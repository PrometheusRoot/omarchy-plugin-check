// The site's compact search index (data/plugins.json): one positional row per plugin, strings that
// repeat (categories, kinds, providers) interned. Built from api/v1/plugins/*.json at build time and
// decoded in the browser; ~4.8k plugins stay a few hundred KB before compression (ADR-0034).
import { areaHits, capHits, commitView, day, primaryReportRow, sortRows } from './model';
import type { Basis, ListingState, PluginDoc, Tier, Verdict } from './types';

export const VERDICTS: readonly Verdict[] = ['safe', 'caution', 'risky', 'blocked', 'unknown'];
const BASES: readonly Basis[] = ['trusted', 'untrusted', 'none'];
const LISTING: readonly ListingState[] = ['listed', 'retired', 'builtin'];

export interface ProviderInfo {
  id: string;
  tier: Tier;
  verification: string;
}

export interface SiteIndex {
  v: 1;
  generatedAt: string;
  catalogGeneratedAt: string | null;
  cats: string[];
  kinds: string[];
  provs: ProviderInfo[];
  rows: CompactRow[];
}

/** Positional row; see `decodeRow` for the field order. */
export type CompactRow = [
  string, // 0 id
  string, // 1 name
  string, // 2 author
  number, // 3 category index (-1 none)
  number, // 4 kind index (-1 none)
  number, // 5 listing state index
  number, // 6 combined verdict index
  number, // 7 basis index
  number, // 8 contested 0/1
  number[], // 9 per provider: [provider index, published verdict index, effective verdict index]*
  number, // 10 stars (-1 unknown)
  number, // 11 rank (0 = unranked)
  string, // 12 updated YYYY-MM-DD
  string, // 13 reviewed YYYY-MM-DD (primary report row)
  number, // 14 risk score of the deciding trusted row (-1 none)
  string, // 15 reviewed commit (7)
  number, // 16 upstream had moved at review time 0/1
  string, // 17 capabilities "key:level key:level"
  string, // 18 system areas "area area"
  string, // 19 network hosts "host host"
  string, // 20 repo "owner/name"
  string, // 21 tags "a b"
  number, // 22 marketplace commit matches reviewed: 1 yes, 0 no, -1 unknown
];

export interface IndexRow {
  id: string;
  name: string;
  author: string;
  cat: string;
  kind: string;
  listing: ListingState;
  verdict: Verdict;
  basis: Basis;
  contested: boolean;
  providers: { id: string; tier: Tier; verification: string; verdict: Verdict; effective: Verdict }[];
  stars: number | null;
  rank: number | null;
  updated: string;
  reviewed: string;
  risk: number | null;
  commit: string;
  moved: boolean;
  caps: { key: string; level: string }[];
  areas: string[];
  hosts: string[];
  repo: string;
  tags: string[];
  mktMatch: boolean | null;
  /** Lower-cased haystack for search. */
  hay: string;
}

const repoPath = (url: string): string => url.replace(/^https:\/\/github\.com\//, '');

function intern(list: string[], map: Map<string, number>, value: string | undefined): number {
  if (!value) return -1;
  let i = map.get(value);
  if (i === undefined) {
    i = list.length;
    list.push(value);
    map.set(value, i);
  }
  return i;
}

/** Build the compact index; rows keep the given document order. */
export function encodeIndex(
  docs: readonly PluginDoc[],
  meta: { generatedAt: string; catalogGeneratedAt: string | null },
  providerOrder: readonly ProviderInfo[],
): SiteIndex {
  const cats: string[] = [];
  const kinds: string[] = [];
  const catMap = new Map<string, number>();
  const kindMap = new Map<string, number>();
  const provs: ProviderInfo[] = [...providerOrder];
  const provIdx = new Map(provs.map((p, i) => [p.id, i]));
  const rows = docs.map((doc): CompactRow => {
    const l = doc.listing;
    const pv: number[] = [];
    for (const r of sortRows(doc.providers)) {
      let i = provIdx.get(r.provider);
      if (i === undefined) {
        i = provs.length;
        provs.push({ id: r.provider, tier: r.tier, verification: r.verification });
        provIdx.set(r.provider, i);
      }
      pv.push(i, VERDICTS.indexOf(r.verdict), VERDICTS.indexOf(r.effectiveVerdict));
    }
    const primary = primaryReportRow(doc.providers);
    const report = primary?.detail?.report;
    const cv = primary ? commitView(primary, doc.providers) : null;
    return [
      doc.id,
      doc.name,
      l?.author ?? '',
      intern(cats, catMap, l?.cat),
      intern(kinds, kindMap, l?.kind),
      LISTING.indexOf(doc.listingState),
      VERDICTS.indexOf(doc.combined.verdict),
      BASES.indexOf(doc.combined.basis),
      doc.combined.contested ? 1 : 0,
      pv,
      l?.gh?.stars ?? -1,
      l?.rank ?? 0,
      l?.updated ? day(l.updated) : '',
      primary?.timeReviewed ? day(primary.timeReviewed) : '',
      l?.verdict?.risk ?? report?.verdict.score ?? -1,
      cv ? cv.reviewed.slice(0, 7) : '',
      cv?.moved ? 1 : 0,
      capHits(report?.capabilities)
        .map((c) => `${c.key}:${c.level}`)
        .join(' '),
      areaHits(report).join(' '),
      (report?.network.hosts ?? []).map((h) => h.host).join(' '),
      repoPath(doc.repo),
      (l?.tags ?? []).join(' '),
      cv?.marketplaceMatch === null || cv === null ? -1 : cv.marketplaceMatch ? 1 : 0,
    ];
  });
  return {
    v: 1,
    generatedAt: meta.generatedAt,
    catalogGeneratedAt: meta.catalogGeneratedAt,
    cats,
    kinds,
    provs,
    rows,
  };
}

const split = (s: string): string[] => (s ? s.split(' ') : []);

/** Decode one positional row into a named record. */
export function decodeRow(idx: Pick<SiteIndex, 'cats' | 'kinds' | 'provs'>, r: CompactRow): IndexRow {
  const providers: IndexRow['providers'] = [];
  for (let i = 0; i + 2 < r[9].length; i += 3) {
    const p = idx.provs[r[9][i] ?? -1];
    if (!p) break;
    providers.push({
      id: p.id,
      tier: p.tier,
      verification: p.verification,
      verdict: VERDICTS[r[9][i + 1] ?? 4] ?? 'unknown',
      effective: VERDICTS[r[9][i + 2] ?? 4] ?? 'unknown',
    });
  }
  const tags = split(r[21]);
  const hosts = split(r[19]);
  const row: IndexRow = {
    id: r[0],
    name: r[1],
    author: r[2],
    cat: idx.cats[r[3]] ?? '',
    kind: idx.kinds[r[4]] ?? '',
    listing: LISTING[r[5]] ?? 'listed',
    verdict: VERDICTS[r[6]] ?? 'unknown',
    basis: BASES[r[7]] ?? 'none',
    contested: r[8] === 1,
    providers,
    stars: r[10] < 0 ? null : r[10],
    rank: r[11] > 0 ? r[11] : null,
    updated: r[12],
    reviewed: r[13],
    risk: r[14] < 0 ? null : r[14],
    commit: r[15],
    moved: r[16] === 1,
    caps: split(r[17]).map((c) => {
      const [key = '', level = 'none'] = c.split(':');
      return { key, level };
    }),
    areas: split(r[18]),
    hosts,
    repo: r[20],
    tags,
    mktMatch: r[22] < 0 ? null : r[22] === 1,
    hay: '',
  };
  row.hay = [row.name, row.id, row.repo, row.author, ...hosts, ...tags].join(' ').toLowerCase();
  return row;
}

export const decodeIndex = (idx: SiteIndex): IndexRow[] => idx.rows.map((r) => decodeRow(idx, r));
