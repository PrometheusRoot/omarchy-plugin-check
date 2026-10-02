// HTML for one index row, shared by the server-rendered first page and the client renderer so both
// produce identical markup. Every interpolated value goes through `esc`.
import type { IndexRow } from './compact';
import { AREAS, CAPS, isCapped, STATE_ICON, type State, verdictState } from './model';
import { rowState } from './query';

const ESC: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export const esc = (s: unknown): string => String(s ?? '').replace(/[&<>"']/g, (c) => ESC[c] ?? c);

/** Inline icon from the sprite; decorative (aria-hidden) — pair it with visible or sr-only text. */
export const icon = (base: string, id: string, cls = ''): string =>
  `<svg class="i ${cls}" aria-hidden="true"><use href="${esc(base)}icons.svg#${id}"/></svg>`;

export const sr = (text: string): string => `<span class="sr">${esc(text)}</span>`;

export const marketplaceUrl = (id: string): string =>
  `https://plugins.omarchy.org/plugin.html?id=${encodeURIComponent(id)}`;

export const pluginHref = (base: string, id: string): string => `${base}plugins/${encodeURIComponent(id)}/`;

export function glyph(base: string, s: State, cls = ''): string {
  return `<span class="glyph c-${s} tip" data-tip="${s}">${icon(base, STATE_ICON[s], cls)}${sr(s)}</span>`;
}

const sigIcon = (base: string, verification: string): string =>
  verification === 'sigstore'
    ? `<span class="sig ok">${icon(base, 'i-sig', 's')}</span>`
    : `<span class="sig no">${icon(base, 'i-unsig', 's')}</span>`;

export function providerChip(base: string, p: IndexRow['providers'][number]): string {
  const pub = verdictState(p.verdict);
  const eff = verdictState(p.effective);
  const short = p.id === 'marketplace' ? 'mkt' : p.id;
  const capped = isCapped(p.tier);
  const sig = p.verification === 'sigstore' ? 'sigstore verified' : p.verification;
  const tip = `${p.id} (${p.tier}): ${pub}${eff !== pub ? ` → counts as ${eff}` : ''}${capped ? ' · capped at caution' : ''} · ${sig}`;
  return `<span class="chip ${pub} tip" data-tip="${esc(tip)}">${esc(short)} ${icon(base, STATE_ICON[pub], 's')}${
    eff !== pub ? `→${icon(base, STATE_ICON[eff], 's')}` : ''
  }${capped ? '<span class="capd" aria-hidden="true">≤</span>' : ''}${sigIcon(base, p.verification)}${sr(tip)}</span>`;
}

export function providerChips(base: string, r: IndexRow): string {
  if (!r.providers.length) return '<span class="chip dim">no provider</span>';
  return r.providers.map((p) => providerChip(base, p)).join('');
}

export function commitChips(base: string, r: IndexRow): string {
  if (r.listing === 'retired') return '<span class="chip retired">retired from marketplace</span>';
  if (!r.commit) return '';
  let h = `<span class="chip brand tip" data-tip="reviewed commit ${esc(r.commit)}">${icon(base, 'i-commit', 's')}<span class="sha">${esc(r.commit)}</span>${sr('reviewed commit')}</span>`;
  h += r.moved
    ? `<span class="chip stale tip" data-tip="upstream had moved past the reviewed commit at review time">${icon(base, 'i-stale', 's')}stale</span>`
    : `<span class="chip tip" data-tip="reviewed commit was upstream HEAD at review time">${icon(base, 'i-check', 's')}head</span>`;
  if (r.mktMatch !== null)
    h += r.mktMatch
      ? `<span class="chip tip" data-tip="marketplace-validated commit = reviewed">${icon(base, 'i-check', 's')}mkt</span>`
      : `<span class="chip caution tip" data-tip="marketplace-validated commit ≠ reviewed">${icon(base, 'i-x', 's')}mkt</span>`;
  return h;
}

export function meter(score: number | null, s: State): string {
  if (score === null) return '<span class="meter none mono mute">—</span>';
  const w = Math.max(0, Math.min(100, score));
  return `<span class="meter" style="--mc:var(--s-${s})" role="img" aria-label="risk ${w} of 100"><span class="bar"><i style="width:${w}%"></i></span><span class="v num">${w}</span></span>`;
}

export function capRow(base: string, caps: IndexRow['caps']): string {
  const hits = caps
    .map((c) => {
      const def = CAPS.find((d) => d.key === c.key);
      if (!def) return '';
      return `<span class="ic ${esc(c.level)} tip" data-tip="${def.short}: ${esc(c.level)} · ${def.desc}">${icon(base, def.icon, 's')}${sr(`${def.short} ${c.level}`)}</span>`;
    })
    .join('');
  return `<span class="irow">${hits || '<span class="mute mono">—</span>'}</span>`;
}

export function areaRow(base: string, areas: readonly string[]): string {
  const hits = AREAS.filter((a) => areas.includes(a.key))
    .map(
      (a) =>
        `<span class="ic hit tip" data-tip="${a.key}">${icon(base, a.icon, 's')}${sr(`touches ${a.key}`)}</span>`,
    )
    .join('');
  return `<span class="irow">${hits || '<span class="mute mono">—</span>'}</span>`;
}

/** One index row. The plugin name is the row's link; the marketplace link sits above it. */
export function rowHtml(base: string, r: IndexRow): string {
  const s = rowState(r);
  const sub = [r.id, r.cat, r.kind.toLowerCase()].filter(Boolean).map(esc).join(' · ');
  const badges =
    (r.listing === 'builtin' ? ' <span class="chip dim">built-in</span>' : '') +
    (r.contested
      ? ` <span class="chip contested tip" data-tip="trusted providers disagree by two levels or more">${icon(base, 'i-flag', 's')}contested</span>`
      : '');
  return `<div class="pl" data-id="${esc(r.id)}">
${glyph(base, s)}
<span class="nm"><b><a class="go" href="${pluginHref(base, r.id)}">${esc(r.name)}</a>${badges}</b><span>${sub} · <a class="ext" href="${marketplaceUrl(r.id)}" rel="noopener" target="_blank">↗ marketplace<span class="sr"> (opens plugins.omarchy.org)</span></a></span><span class="cm">${commitChips(base, r)}</span></span>
${meter(r.risk, s)}
<span class="ir1">${capRow(base, r.caps)}</span>
<span class="ir2">${areaRow(base, r.areas)}</span>
<span class="pv">${providerChips(base, r)}</span>
<span class="star">${icon(base, 'i-star', 's')}<span class="num">${r.stars === null ? '—' : r.stars.toLocaleString('en-US')}</span>${sr('stars')}</span>
<span class="when num">${r.reviewed || '—'}</span>
</div>`;
}
