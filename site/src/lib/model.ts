// Pure display model: API documents in, display values out. No I/O, no DOM (ADR-0004 spirit; the
// same module runs at build time in Astro and in the browser bundle). Unit-tested in tests/unit.
import type {
  Capability,
  Criteria,
  Level,
  ListingState,
  PluginDoc,
  ProviderRow,
  Report,
  ReportFinding,
  Severity,
  Tier,
  Verdict,
} from './types';

/** What the site shows for a plugin: a verdict, or a listing state that replaces it. */
export type State = 'safe' | 'caution' | 'risky' | 'blocked' | 'unreviewed' | 'retired' | 'unlisted';

export const STATES: readonly State[] = [
  'safe',
  'caution',
  'risky',
  'blocked',
  'unreviewed',
  'retired',
  'unlisted',
];

/** Icon id (public/icons.svg) per state and per verdict as published. */
export const STATE_ICON: Record<State, string> = {
  safe: 'i-safe',
  caution: 'i-caution',
  risky: 'i-risky',
  blocked: 'i-blocked',
  unreviewed: 'i-unreviewed',
  retired: 'i-retired',
  unlisted: 'i-unlisted',
};

/** Severity order for "worst first" sorting; listing states sort below every verdict. */
const STATE_RANK: Record<State, number> = {
  blocked: 5,
  risky: 4,
  caution: 3,
  safe: 2,
  unreviewed: 1,
  retired: 0,
  unlisted: 0,
};

export const stateRank = (s: State): number => STATE_RANK[s];

/** A provider verdict as a state: `unknown` reads as unreviewed. */
export const verdictState = (v: Verdict): State => (v === 'unknown' ? 'unreviewed' : v);

/** The state of a plugin: retired replaces the verdict (no verdict is computed for it). */
export function pluginState(listingState: ListingState, verdict: Verdict): State {
  if (listingState === 'retired') return 'retired';
  return verdictState(verdict);
}

export const TIER_NOTE: Record<Tier, string> = {
  core: 'counts fully in combined',
  verified: 'counts fully in combined',
  community: 'capped: can raise combined to at most caution',
  unsigned: 'unsigned: capped at caution',
};

const TIER_ORDER: Record<Tier, number> = { core: 0, verified: 1, community: 2, unsigned: 3 };

export const isCapped = (t: Tier): boolean => t === 'community' || t === 'unsigned';
export const isTrusted = (t: Tier): boolean => t === 'core' || t === 'verified';

/** Short provider label for chips (marketplace → mkt). */
export const providerShort = (id: string): string => (id === 'marketplace' ? 'mkt' : id);

/** Rows in display order: tier (core first), then provider id. */
export function sortRows(rows: readonly ProviderRow[]): ProviderRow[] {
  return [...rows].sort(
    (a, b) => TIER_ORDER[a.tier] - TIER_ORDER[b.tier] || a.provider.localeCompare(b.provider),
  );
}

/**
 * The row whose report the page shows first: a trusted row with an embedded report (latest review
 * first), else any row with a report, else null.
 */
export function primaryReportRow(rows: readonly ProviderRow[]): ProviderRow | null {
  const withReport = rows.filter((r) => r.detail?.report);
  const score = (r: ProviderRow) => (isTrusted(r.tier) ? 1 : 0);
  withReport.sort(
    (a, b) => score(b) - score(a) || (b.timeReviewed ?? '').localeCompare(a.timeReviewed ?? ''),
  );
  return withReport[0] ?? null;
}

/** What a row contributes to the combined verdict, as the aggregator decided it. */
export function countsAs(row: ProviderRow): { state: State | null; capped: boolean } {
  if (!row.counted) return { state: null, capped: false };
  return { state: verdictState(row.effectiveVerdict), capped: isCapped(row.tier) };
}

export const ADJUSTMENT_TEXT: Record<string, string> = {
  'capped-at-caution': 'capped at caution (tier)',
  'blocked-without-evidence': 'blocked without file:line evidence → risky',
};

// ---- criteria ----

export const CRITERIA: readonly { id: string; short: string }[] = [
  { id: 'safe-to-run', short: 'safe-to-run' },
  { id: 'no-network', short: 'no-net' },
  { id: 'no-exec', short: 'no-exec' },
  { id: 'no-persistence', short: 'no-persist' },
  { id: 'no-privilege', short: 'no-priv' },
  { id: 'no-obfuscation', short: 'no-obfusc' },
  { id: 'no-secrets', short: 'no-secrets' },
  { id: 'reviewed-by-human', short: 'human' },
];

export type CriterionState = 'pass' | 'fail' | 'na';

/** Every criterion of the vocabulary: pass (checked, not failed), fail, or na (not checked). */
export function criteriaView(
  c: Criteria | undefined,
): { id: string; short: string; state: CriterionState }[] {
  const checked = new Set(c?.checked ?? []);
  const failed = new Set(c?.failed ?? []);
  return CRITERIA.map(({ id, short }) => ({
    id,
    short,
    state: failed.has(id) ? 'fail' : checked.has(id) ? 'pass' : 'na',
  }));
}

// ---- capabilities + system areas ----

export const CAPS: readonly { key: string; short: string; icon: string; desc: string }[] = [
  { key: 'processExec', short: 'exec', icon: 'i-exec', desc: 'spawns processes' },
  { key: 'network', short: 'net', icon: 'i-net', desc: 'reaches the network' },
  { key: 'fileWrite', short: 'write', icon: 'i-write', desc: 'writes outside its dir' },
  { key: 'persistence', short: 'persist', icon: 'i-persist', desc: 'survives restart' },
  { key: 'privilege', short: 'priv', icon: 'i-priv', desc: 'sudo / pkexec / polkit' },
  { key: 'packageInstall', short: 'pkg', icon: 'i-pkg', desc: 'installs packages' },
  { key: 'bundledBinary', short: 'bin', icon: 'i-bin', desc: 'ships binaries' },
  { key: 'clipboard', short: 'clip', icon: 'i-clip', desc: 'reads/writes clipboard' },
  { key: 'screenCapture', short: 'screen', icon: 'i-cam', desc: 'captures screen' },
  { key: 'hyprlandIpc', short: 'hypr', icon: 'i-hypr', desc: 'controls the compositor' },
  { key: 'externalCode', short: 'ext', icon: 'i-link', desc: 'runs code it does not ship' },
];

export const AREAS: readonly { key: string; short: string; icon: string }[] = [
  { key: 'omarchy-shell', short: 'shell', icon: 'i-shell' },
  { key: 'hyprland', short: 'hypr', icon: 'i-layers' },
  { key: 'systemd', short: 'systemd', icon: 'i-systemd' },
  { key: 'pacman-aur', short: 'pacman', icon: 'i-pacman' },
  { key: 'sudoers', short: 'sudoers', icon: 'i-lock' },
  { key: 'shell-rc', short: 'rc', icon: 'i-rc' },
  { key: 'ssh', short: 'ssh', icon: 'i-ssh' },
  { key: 'browsers', short: 'browsers', icon: 'i-browser' },
  { key: 'gpg', short: 'gpg', icon: 'i-gpg' },
  { key: 'dbus', short: 'dbus', icon: 'i-dbus' },
];

const LEVELS: readonly Level[] = ['none', 'low', 'med', 'high'];
export const asLevel = (v: unknown): Level => (LEVELS.includes(v as Level) ? (v as Level) : 'none');

/** Capabilities above `none`, in vocabulary order, as `short:level` pairs. */
export function capHits(caps: Record<string, Capability> | undefined): { key: string; level: Level }[] {
  if (!caps) return [];
  return CAPS.flatMap(({ key }) => {
    const level = asLevel(caps[key]?.level);
    return level === 'none' ? [] : [{ key, level }];
  });
}

/** System areas the report marks as touched, in vocabulary order. */
export function areaHits(report: Pick<Report, 'systemAreas'> | undefined): string[] {
  const touched = new Set(report?.systemAreas?.touched ?? []);
  return AREAS.filter((a) => touched.has(a.key)).map((a) => a.key);
}

// ---- commits ----

export const sha7 = (s: string | null | undefined): string => (s ? s.slice(0, 7) : '—');
export const day = (s: string | null | undefined): string => (s ? s.slice(0, 10) : '—');

export interface CommitView {
  reviewed: string;
  tree: string | null;
  /** Upstream default-branch HEAD when the review ran (null = unknown). */
  upstreamAtScan: string | null;
  /** Upstream had moved past the reviewed commit when it was reviewed. */
  moved: boolean;
  /** Marketplace-validated commit, if the marketplace row names one. */
  marketplace: string | null;
  marketplaceMatch: boolean | null;
}

/** Commit chips for a reviewed row: reviewed sha, upstream head, marketplace-validated commit. */
export function commitView(row: ProviderRow, rows: readonly ProviderRow[]): CommitView | null {
  if (!row.commit) return null;
  const report = row.detail?.report;
  const up = report?.review.upstreamHeadAtScan ?? null;
  const mkt = rows.find((r) => r.provider === 'marketplace')?.commit ?? null;
  return {
    reviewed: row.commit,
    tree: row.tree ?? null,
    upstreamAtScan: up,
    moved: up !== null && up !== row.commit,
    marketplace: mkt,
    marketplaceMatch: mkt === null ? null : mkt === row.commit,
  };
}

// ---- report helpers ----

/** Hotspot reasons without opaque rule identifiers (ADR-0011): `r.<hex>` tokens are dropped. */
export function publicReason(reason: string): string {
  const parts = reason
    .split(/[;,]\s*/)
    .map((p) => p.trim())
    .filter((p) => p && !/^r\.[0-9a-f]{6,}$/i.test(p));
  return parts.join(' · ');
}

const SEVERITY_ORDER: Record<Severity, number> = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };

/** Findings worst first, then by path and line; split into notable (above info) and info. */
export function splitFindings(findings: readonly ReportFinding[]): {
  notable: ReportFinding[];
  info: ReportFinding[];
} {
  const sorted = [...findings].sort(
    (a, b) =>
      SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] ||
      a.path.localeCompare(b.path) ||
      a.line - b.line,
  );
  return {
    notable: sorted.filter((f) => f.severity !== 'info'),
    info: sorted.filter((f) => f.severity === 'info'),
  };
}

export const severityChip = (s: Severity): string =>
  s === 'critical' || s === 'high' ? 'blocked' : s === 'medium' ? 'caution' : '';

/** AI pass-2 verdict per finding id (the report's `pass2` list, else the finding's own field). */
export function aiVerdicts(report: Report): Map<string, 'confirmed' | 'likely-fp' | 'unsure'> {
  const out = new Map<string, 'confirmed' | 'likely-fp' | 'unsure'>();
  for (const f of report.findings) if (f.aiVerified) out.set(f.id, f.aiVerified);
  for (const p of report.ai?.pass2 ?? []) out.set(p.findingId, p.verdict);
  return out;
}

/** Normalised 52-week activity for a sparkline (nulls = unknown → 0), or null when all unknown. */
export function activitySeries(weeks: readonly (number | null)[] | undefined): number[] | null {
  if (!weeks || weeks.every((w) => w === null)) return null;
  return weeks.map((w) => w ?? 0);
}

/** SVG polyline points for a sparkline in a w×h box. */
export function sparkPoints(vals: readonly number[], w = 300, h = 48): [number, number][] {
  const max = Math.max(1, ...vals);
  const n = vals.length;
  const step = n > 1 ? (w - 8) / (n - 1) : 0;
  return vals.map((v, i) => [
    Math.round((4 + i * step) * 10) / 10,
    Math.round((h - 4 - (v / max) * (h - 12)) * 10) / 10,
  ]);
}

/** One-line description of why the combined verdict is what it is. */
export function combinedNote(doc: Pick<PluginDoc, 'combined' | 'providers' | 'listingState'>): string {
  if (doc.listingState === 'retired') return 'retired from plugins.omarchy.org · no verdict is computed';
  const counted = doc.providers.filter((r) => r.counted);
  const trusted = counted.filter((r) => isTrusted(r.tier)).length;
  switch (doc.combined.basis) {
    case 'trusted':
      return `combined · worst of core + verified (${trusted} trusted, ${counted.length} counted)`;
    case 'untrusted':
      return 'no trusted review · capped providers only (≤ caution, never safe)';
    default:
      return 'no provider has a decided verdict';
  }
}

export const fmtInt = (n: number | null | undefined): string =>
  n === null || n === undefined ? '—' : n.toLocaleString('en-US');
