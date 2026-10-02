# site — the public website

Astro 5, fully static (ADR-0034). Built from the aggregator's `api/v1/` and deployed to GitHub
Pages with the static API next to it. Independent community project, not affiliated with Omarchy.

| Path | What |
|---|---|
| `/` | index: search (name, id, repo, host), verdict / category / kind filters, sort, 50-row pages |
| `/plugins/<id>/` | report: combined verdict, every provider's row, the provider's report sections |
| `/providers/` | registry: tier, signing identity, validity, coverage |
| `/about/`, `/api/` | trust model + checker install; endpoints, schemas, signature verification |
| `/api/v1/…`, `/store*.json`, `/spec/v1/*.schema.json`, `/keys/` | copied verbatim at build time |
| `/data/plugins.json` | the index page's compact search data (not a stable API) |

## Build settings (environment)

| Variable | Default |
|---|---|
| `OPC_API_DIR` | the local dev snapshot's `api/v1` (see `src/lib/env.ts`) |
| `OPC_SNAPSHOT_DIR` | the directory above `api/` if it holds `store.json` |
| `OPC_REGISTRY` | `providers.json` next to the snapshot, else the dev registry |
| `OPC_SITE_BASE` | `/omarchy-plugin-check/` |
| `OPC_SITE_URL` | `https://prometheusroot.github.io` |

## Develop

```sh
cd site && npm ci
just site-dev            # astro dev
just site-build          # dist/ + build time and size
just site-lint           # biome + astro check
just site-test           # vitest + 4 playwright specs over tests/fixtures (PLAYWRIGHT_CHROMIUM=/usr/bin/chromium)
OPC_SITE_BASE=/ OPC_API_DIR=tests/fixtures/api/v1 npx astro build && npx lhci autorun
```

`src/lib/` is pure (model, compact index, query, row renderer; unit-tested); `src/lib/data.ts` is
the only build-time I/O; `src/client/` holds the three small browser scripts. The fixture is
regenerated with `node scripts/make-fixture.mjs <snapshot>/api/v1 [providers.json]`.
