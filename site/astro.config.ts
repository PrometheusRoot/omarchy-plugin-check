// Static site over the aggregator's api/v1 (ADR-0034). Base path and data dirs come from the
// environment (src/lib/env.ts): OPC_API_DIR, OPC_SNAPSHOT_DIR, OPC_REGISTRY, OPC_SITE_BASE, OPC_SITE_URL.
import { createReadStream, existsSync, statSync } from 'node:fs';
import { copyFile, cp } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { defineConfig } from 'astro/config';
import { siteEnv } from './src/lib/env';

const env = siteEnv();

/** Snapshot-root files the CLI and the store app fetch (spec/PROTOCOL.md §6, §7). */
const SNAPSHOT_FILES = [
  'store.json',
  'store.json.sig',
  'store-manifest.json',
  'store-manifest.json.sig',
  'store-home.json',
  'store-search.json',
  'store-details.json',
];

/** Serve api/v1 + snapshot files in `astro dev`; copy them verbatim into dist after the build. */
function staticApi(): AstroIntegration {
  const mounts = (): [string, string][] => {
    const m: [string, string][] = [[`${env.base}api/v1/`, env.apiDir]];
    if (env.snapshotDir)
      for (const f of SNAPSHOT_FILES) m.push([`${env.base}${f}`, join(env.snapshotDir, f)]);
    if (env.registry) m.push([`${env.base}providers.json`, env.registry]);
    return m;
  };
  let siteRoot = process.cwd();
  return {
    name: 'opc-static-api',
    hooks: {
      'astro:config:done': ({ config }) => {
        siteRoot = fileURLToPath(config.root);
      },
      'astro:server:setup': ({ server }) => {
        server.middlewares.use((req, res, next) => {
          const url = decodeURIComponent((req.url ?? '').split('?')[0] ?? '');
          for (const [prefix, target] of mounts()) {
            if (!url.startsWith(prefix)) continue;
            const file = prefix.endsWith('/') ? normalize(join(target, url.slice(prefix.length))) : target;
            if (!file.startsWith(target) || !existsSync(file) || !statSync(file).isFile()) break;
            const type = extname(file) === '.json' ? 'application/json' : 'application/octet-stream';
            res.setHeader('content-type', type);
            createReadStream(file).pipe(res);
            return;
          }
          next();
        });
      },
      'astro:build:done': async ({ dir, logger }) => {
        const out = fileURLToPath(dir);
        await cp(env.apiDir, join(out, 'api', 'v1'), { recursive: true });
        logger.info(`copied ${env.apiDir} → dist/api/v1`);
        if (env.snapshotDir) {
          for (const f of SNAPSHOT_FILES) {
            const src = join(env.snapshotDir, f);
            if (existsSync(src)) await copyFile(src, join(out, f));
          }
          logger.info(`copied snapshot files from ${env.snapshotDir}`);
        }
        // Schemas at their $id (…/spec/v1/<name>.schema.json) and the public verification keys.
        const repo = join(siteRoot, '..');
        await cp(join(repo, 'spec', 'schemas'), join(out, 'spec', 'v1'), { recursive: true });
        await cp(join(repo, 'spec', 'keys'), join(out, 'keys'), {
          recursive: true,
          filter: (src) => !src.endsWith('.md'),
        });
        if (env.registry) {
          await copyFile(env.registry, join(out, 'providers.json'));
          if (existsSync(`${env.registry}.sig`))
            await copyFile(`${env.registry}.sig`, join(out, 'providers.json.sig'));
        }
      },
    },
  };
}

export default defineConfig({
  site: env.site,
  base: env.base,
  output: 'static',
  trailingSlash: 'always',
  build: { format: 'directory', concurrency: 4 },
  compressHTML: true,
  integrations: [staticApi()],
  devToolbar: { enabled: false },
});
