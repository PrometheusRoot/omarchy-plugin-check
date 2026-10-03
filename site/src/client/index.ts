// Index page: loads the compact index once, then search / filter / sort / paginate client-side.
// The first page is server-rendered with the same row renderer (src/lib/render.ts).
import { decodeIndex, type IndexRow, type SiteIndex } from '../lib/compact';
import {
  DEFAULT_DIR,
  fromParams,
  PAGE_SIZE,
  type Query,
  run,
  type SortKey,
  type StateFilter,
  toParams,
} from '../lib/query';
import { rowHtml } from '../lib/render';

const root = document.getElementById('index');
const base = root?.dataset.base ?? '/';
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T | null;
const input = $<HTMLInputElement>('q');
const cat = $<HTMLSelectElement>('cat');
const kind = $<HTMLSelectElement>('kind');
const sortSel = $<HTMLSelectElement>('sort');
const rowsEl = $('rows');
const status = $('status');
const range = $('range');
const pageno = $('pageno');
const prev = $<HTMLButtonElement>('prev');
const next = $<HTMLButtonElement>('next');
const reviewedOnly = $<HTMLButtonElement>('reviewedOnly');

let rows: IndexRow[] | null = null;
let query: Query = fromParams(new URLSearchParams(location.search));

const SORT_LABEL: Record<SortKey, string> = {
  rank: 'rank',
  name: 'name',
  risk: 'risk',
  stars: 'stars',
  reviewed: 'last review',
  verdict: 'worst first',
};

function syncControls(): void {
  if (input && input.value !== query.q) input.value = query.q;
  if (cat) cat.value = query.cat;
  if (kind) kind.value = query.kind;
  if (sortSel) sortSel.value = query.sort;
  reviewedOnly?.setAttribute('aria-pressed', String(query.reviewedOnly));
  for (const b of document.querySelectorAll<HTMLButtonElement>('#filters [data-f]'))
    b.setAttribute('aria-pressed', String(b.dataset.f === query.state));
  for (const b of document.querySelectorAll<HTMLButtonElement>('.hd [data-sort]')) {
    const on = b.dataset.sort === query.sort;
    b.setAttribute('aria-pressed', String(on));
    if (on) b.dataset.dir = query.dir;
    else delete b.dataset.dir;
  }
}

function render(push = false): void {
  syncControls();
  if (!rows || !rowsEl) return;
  const res = run(rows, query);
  query.page = res.page;
  rowsEl.innerHTML = res.rows.length
    ? res.rows.map((r) => rowHtml(base, r)).join('')
    : '<div class="empty">no plugins match</div>';
  for (const el of document.querySelectorAll<HTMLElement>('[data-count]')) {
    el.textContent = String(res.counts[el.dataset.count as StateFilter] ?? 0);
  }
  const from = res.total ? (res.page - 1) * PAGE_SIZE + 1 : 0;
  const to = Math.min(res.page * PAGE_SIZE, res.total);
  const sorted = `sorted by ${SORT_LABEL[query.sort]}${query.dir === DEFAULT_DIR[query.sort] ? '' : ' (reversed)'}`;
  if (range) range.textContent = `${from}–${to} of ${res.total.toLocaleString('en-US')} · ${sorted}`;
  if (pageno) pageno.textContent = `${res.page} / ${res.pages}`;
  if (prev) prev.disabled = res.page <= 1;
  if (next) next.disabled = res.page >= res.pages;
  if (status) status.textContent = `${res.total} plugins match`;
  const qs = toParams(query).toString();
  const url = `${location.pathname}${qs ? `?${qs}` : ''}`;
  try {
    if (push) history.pushState(null, '', url);
    else history.replaceState(null, '', url);
  } catch {
    // history unavailable (sandboxed frame): state stays in memory
  }
}

let timer: number | undefined;

function update(patch: Partial<Query>, opts: { keepPage?: boolean; push?: boolean } = {}): void {
  // A typed query still waiting for its debounce goes in now: otherwise render() would write the
  // old query back into the box and the pending update would then re-apply it.
  if (timer !== undefined) {
    window.clearTimeout(timer);
    timer = undefined;
    if (input && patch.q === undefined) patch = { ...patch, q: input.value };
  }
  query = { ...query, ...patch, page: opts.keepPage ? (patch.page ?? query.page) : (patch.page ?? 1) };
  render(opts.push);
}

input?.addEventListener('input', () => {
  window.clearTimeout(timer);
  timer = window.setTimeout(() => {
    timer = undefined;
    update({ q: input.value });
  }, 60);
});
cat?.addEventListener('change', () => update({ cat: cat.value }));
kind?.addEventListener('change', () => update({ kind: kind.value }));
sortSel?.addEventListener('change', () => {
  const s = sortSel.value as SortKey;
  update({ sort: s, dir: DEFAULT_DIR[s] });
});
reviewedOnly?.addEventListener('click', () => update({ reviewedOnly: !query.reviewedOnly }));
for (const b of document.querySelectorAll<HTMLButtonElement>('#filters [data-f]'))
  b.addEventListener('click', () => update({ state: b.dataset.f as StateFilter }));
for (const b of document.querySelectorAll<HTMLButtonElement>('.hd [data-sort]')) {
  b.addEventListener('click', () => {
    const s = b.dataset.sort as SortKey;
    const dir = query.sort === s ? (query.dir === 'asc' ? 'desc' : 'asc') : DEFAULT_DIR[s];
    update({ sort: s, dir });
  });
}
const go = (page: number) => {
  update({ page }, { keepPage: true, push: true });
  root?.scrollIntoView({ block: 'start' });
};
prev?.addEventListener('click', () => go(query.page - 1));
next?.addEventListener('click', () => go(query.page + 1));
window.addEventListener('popstate', () => {
  query = fromParams(new URLSearchParams(location.search));
  render();
});
document.addEventListener('keydown', (e) => {
  if (e.key === '/' && document.activeElement !== input && !(e.target instanceof HTMLInputElement)) {
    e.preventDefault();
    input?.focus();
  }
});

// The server-rendered first page is already the default view, so the search data (0.8 MB, ~0.2 MB
// compressed) loads only when the URL carries a query or the reader starts using the controls.
let loading: Promise<void> | null = null;
function ensureData(): Promise<void> {
  loading ??= fetch(`${base}data/plugins.json`)
    .then((r) => (r.ok ? (r.json() as Promise<SiteIndex>) : Promise.reject(new Error(String(r.status)))))
    .then((idx) => {
      rows = decodeIndex(idx);
      if (input?.value && input.value !== query.q) query.q = input.value;
      render();
    })
    .catch(() => {
      if (status) status.textContent = 'search data failed to load; showing the first page only';
    });
  return loading;
}

syncControls();
if (location.search) void ensureData();
for (const ev of ['pointerdown', 'focusin', 'keydown'] as const) {
  root?.addEventListener(ev, () => void ensureData(), { once: true, passive: true });
}
document.addEventListener('keydown', (e) => {
  if (e.key === '/') void ensureData();
});
