// Build settings from the environment (read by astro.config.ts and the build-time data loader).
import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

// why: the dev default is a local snapshot build (scripts/build-snapshot.sh --out .snapshot) at the
// repo root, relative to site/ where every recipe runs; it is gitignored. CI sets OPC_API_DIR.
const DEV_SNAPSHOT = '../.snapshot';

function withSlashes(base: string): string {
  const b = base.trim() || '/';
  return `${b.startsWith('/') ? '' : '/'}${b}${b.endsWith('/') ? '' : '/'}`;
}

export interface SiteEnv {
  /** Built `api/v1/` directory (meta.json, index.json, plugins/). */
  apiDir: string;
  /** Snapshot root next to `api/` (store.json + client bundle), copied to the site root if present. */
  snapshotDir: string | null;
  /** Provider registry (providers.json) for the providers page; optional. */
  registry: string | null;
  /** Base path, always with leading and trailing slash. */
  base: string;
  /** Absolute origin of the deployed site (canonical URLs). */
  site: string;
}

export function siteEnv(env: Record<string, string | undefined> = process.env): SiteEnv {
  const apiDir = resolve(env.OPC_API_DIR || `${DEV_SNAPSHOT}/api/v1`);
  const guessRoot = dirname(dirname(apiDir));
  const snapshotDir = env.OPC_SNAPSHOT_DIR
    ? resolve(env.OPC_SNAPSHOT_DIR)
    : existsSync(`${guessRoot}/store.json`)
      ? guessRoot
      : null;
  const registry = env.OPC_REGISTRY
    ? resolve(env.OPC_REGISTRY)
    : existsSync(`${apiDir}/../../providers.json`)
      ? resolve(`${apiDir}/../../providers.json`)
      : null;
  return {
    apiDir,
    snapshotDir,
    registry,
    base: withSlashes(env.OPC_SITE_BASE ?? '/omarchy-plugin-check/'),
    site: env.OPC_SITE_URL || 'https://prometheusroot.github.io',
  };
}
