// Build-time data access: reads the built api/v1 directory once per build (synchronous fs, memoised).
// Only Astro pages and the build integration import this module; the browser never does.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { encodeIndex, type ProviderInfo, type SiteIndex } from './compact';
import { siteEnv } from './env';
import type { Meta, PluginDoc, Registry } from './types';

interface Data {
  meta: Meta;
  docs: PluginDoc[];
  byId: Map<string, PluginDoc>;
  registry: Registry | null;
}

let cache: Data | null = null;

const readJson = <T>(path: string): T => JSON.parse(readFileSync(path, 'utf8')) as T;

/** Rank order (marketplace + activity ranking, docs/RANKING.md); unranked plugins last, by id. */
const byRank = (a: PluginDoc, b: PluginDoc): number =>
  (a.listing?.rank ?? Number.MAX_SAFE_INTEGER) - (b.listing?.rank ?? Number.MAX_SAFE_INTEGER) ||
  a.id.localeCompare(b.id);

export function load(): Data {
  if (cache) return cache;
  const env = siteEnv();
  const metaPath = join(env.apiDir, 'meta.json');
  if (!existsSync(metaPath)) {
    throw new Error(
      `OPC_API_DIR=${env.apiDir} has no meta.json; build a snapshot (just snapshot) or point OPC_API_DIR at api/v1`,
    );
  }
  const meta = readJson<Meta>(metaPath);
  const dir = join(env.apiDir, 'plugins');
  const docs = readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.json'))
    .map((e) => readJson<PluginDoc>(join(dir, e.name)))
    .sort(byRank);
  const registry = env.registry && existsSync(env.registry) ? readJson<Registry>(env.registry) : null;
  cache = { meta, docs, byId: new Map(docs.map((d) => [d.id, d])), registry };
  return cache;
}

export function providerOrder(meta: Meta): ProviderInfo[] {
  return meta.providers.map((p) => ({ id: p.id, tier: p.tier, verification: p.verification }));
}

export function siteIndex(): SiteIndex {
  const { meta, docs } = load();
  return encodeIndex(
    docs,
    { generatedAt: meta.generatedAt, catalogGeneratedAt: meta.catalogGeneratedAt },
    providerOrder(meta),
  );
}

/** Plugins each provider has a row for, and how many per published verdict. */
export function coverage(): Map<string, { rows: number; verdicts: Record<string, number>; ids: string[] }> {
  const out = new Map<string, { rows: number; verdicts: Record<string, number>; ids: string[] }>();
  for (const d of load().docs) {
    for (const r of d.providers) {
      const c = out.get(r.provider) ?? { rows: 0, verdicts: {}, ids: [] };
      c.rows += 1;
      c.verdicts[r.verdict] = (c.verdicts[r.verdict] ?? 0) + 1;
      if (r.detail?.report || r.tier !== 'unsigned') c.ids.push(d.id);
      out.set(r.provider, c);
    }
  }
  return out;
}
