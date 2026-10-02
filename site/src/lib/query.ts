// Index query: filter, sort and paginate decoded rows. Pure; the index page runs it per keystroke
// over ~4.8k rows (tests/unit/query.test.ts keeps it well under a frame).
import type { IndexRow } from './compact';
import { pluginState, type State, stateRank } from './model';

export type SortKey = 'rank' | 'name' | 'risk' | 'stars' | 'reviewed' | 'verdict';
export type Dir = 'asc' | 'desc';
export type StateFilter = 'all' | State;

export interface Query {
  q: string;
  state: StateFilter;
  cat: string;
  kind: string;
  reviewedOnly: boolean;
  sort: SortKey;
  dir: Dir;
  page: number;
}

export const PAGE_SIZE = 50;

export const DEFAULT_QUERY: Query = {
  q: '',
  state: 'all',
  cat: '',
  kind: '',
  reviewedOnly: false,
  sort: 'rank',
  dir: 'asc',
  page: 1,
};

/** The direction a sort key starts in when first chosen. */
export const DEFAULT_DIR: Record<SortKey, Dir> = {
  rank: 'asc',
  name: 'asc',
  risk: 'desc',
  stars: 'desc',
  reviewed: 'desc',
  verdict: 'desc',
};

export const rowState = (r: Pick<IndexRow, 'listing' | 'verdict'>): State =>
  pluginState(r.listing, r.verdict);

const terms = (q: string): string[] => q.toLowerCase().trim().split(/\s+/).filter(Boolean);

/** 0 = name/id starts with the query, 1 = contains it as a whole, 2 = all terms match somewhere. */
function relevance(r: IndexRow, q: string): number {
  const name = r.name.toLowerCase();
  if (name.startsWith(q) || r.id.startsWith(q)) return 0;
  if (name.includes(q) || r.id.includes(q)) return 1;
  return 2;
}

function compare(a: IndexRow, b: IndexRow, key: SortKey): number {
  switch (key) {
    case 'name':
      return a.name.localeCompare(b.name, 'en', { sensitivity: 'base' });
    case 'risk':
      return (a.risk ?? -1) - (b.risk ?? -1);
    case 'stars':
      return (a.stars ?? -1) - (b.stars ?? -1);
    case 'reviewed':
      return a.reviewed.localeCompare(b.reviewed);
    case 'verdict':
      return stateRank(rowState(a)) - stateRank(rowState(b));
    default:
      return (a.rank ?? Number.MAX_SAFE_INTEGER) - (b.rank ?? Number.MAX_SAFE_INTEGER);
  }
}

/** Rows matching q + category + kind + reviewed-only (not the state filter): the base for counts. */
export function matchBase(rows: readonly IndexRow[], query: Query): IndexRow[] {
  const ts = terms(query.q);
  return rows.filter(
    (r) =>
      (!query.cat || r.cat === query.cat) &&
      (!query.kind || r.kind === query.kind) &&
      (!query.reviewedOnly || r.commit !== '') &&
      ts.every((t) => r.hay.includes(t)),
  );
}

export function stateCounts(rows: readonly IndexRow[]): Record<StateFilter, number> {
  const out = { all: rows.length } as Record<StateFilter, number>;
  for (const r of rows) {
    const s = rowState(r);
    out[s] = (out[s] ?? 0) + 1;
  }
  return out;
}

export interface Result {
  total: number;
  page: number;
  pages: number;
  rows: IndexRow[];
  counts: Record<StateFilter, number>;
}

export function run(rows: readonly IndexRow[], query: Query): Result {
  const base = matchBase(rows, query);
  const counts = stateCounts(base);
  const hits = query.state === 'all' ? base : base.filter((r) => rowState(r) === query.state);
  const q = query.q.toLowerCase().trim();
  const sign = query.dir === 'asc' ? 1 : -1;
  const sorted = [...hits].sort((a, b) => {
    if (q && query.sort === 'rank') {
      const d = relevance(a, q) - relevance(b, q);
      if (d) return d;
    }
    return sign * compare(a, b, query.sort) || compare(a, b, 'rank') || a.id.localeCompare(b.id);
  });
  const pages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE));
  const page = Math.min(Math.max(1, query.page), pages);
  return {
    total: sorted.length,
    page,
    pages,
    rows: sorted.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE),
    counts,
  };
}

const SORTS: readonly SortKey[] = ['rank', 'name', 'risk', 'stars', 'reviewed', 'verdict'];
const STATE_FILTERS: readonly StateFilter[] = [
  'all',
  'safe',
  'caution',
  'risky',
  'blocked',
  'unreviewed',
  'retired',
];

/** Query from URL search params (unknown values fall back to defaults). */
export function fromParams(p: URLSearchParams): Query {
  const sort = p.get('sort') as SortKey | null;
  const state = p.get('v') as StateFilter | null;
  const s: SortKey = sort && SORTS.includes(sort) ? sort : DEFAULT_QUERY.sort;
  const dir = p.get('dir');
  const page = Number.parseInt(p.get('page') ?? '1', 10);
  return {
    q: p.get('q') ?? '',
    state: state && STATE_FILTERS.includes(state) ? state : 'all',
    cat: p.get('cat') ?? '',
    kind: p.get('kind') ?? '',
    reviewedOnly: p.get('reviewed') === '1',
    sort: s,
    dir: dir === 'asc' || dir === 'desc' ? dir : DEFAULT_DIR[s],
    page: Number.isFinite(page) && page > 0 ? page : 1,
  };
}

/** URL search params for a query; defaults are omitted so the plain index URL stays clean. */
export function toParams(q: Query): URLSearchParams {
  const p = new URLSearchParams();
  if (q.q) p.set('q', q.q);
  if (q.state !== 'all') p.set('v', q.state);
  if (q.cat) p.set('cat', q.cat);
  if (q.kind) p.set('kind', q.kind);
  if (q.reviewedOnly) p.set('reviewed', '1');
  if (q.sort !== 'rank') p.set('sort', q.sort);
  if (q.dir !== DEFAULT_DIR[q.sort]) p.set('dir', q.dir);
  if (q.page > 1) p.set('page', String(q.page));
  return p;
}
