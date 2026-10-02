# 0036. The site is a static Astro build over api/v1, with a compact client index

- Status: accepted
- Date: 2026-10-02
- Supersedes: —

## Context

The site must show ~4,800 plugins (search, filters, sort) and a full report per plugin, from the
aggregator's api/v1, on GitHub Pages under a subpath. The index must not download 20 MB; the
build must stay under 3 minutes; the published API must be byte-identical to what clients verify.

## Decision

**Astro 5 builds one static page per plugin straight from `api/v1/plugins/*.json` (plain `fs` at
build time, no content collections), the index searches a compact positional index
(`data/plugins.json`) client-side with 50-row pages, and the build copies `api/v1/` (plus the
signed snapshot files, schemas and public keys) into `dist/` verbatim.**

## Consequences

- Measured on the dev snapshot (4,777 plugins): 4,782 pages in ~37 s, dist 105 MB; the index
  data is 0.8 MB raw / 0.2 MB gzip and a query over 4.8k rows takes well under a frame. The
  fallback (static pages only for reviewed plugins + one client-rendered page) is not needed.
- One row renderer (`src/lib/render.ts`) serves the server-rendered first page and the client,
  so no-JS readers get page one; the URL carries the query (`?q=&v=&sort=`).
- The base path (`OPC_SITE_BASE`) and data dirs are environment settings; no page hard-codes a
  path. Unknown `plugins/<id>/` URLs render the *unlisted* state (404 page).
- Reports never show rule ids or score formulas (ADR-0011): `ruleId` is dropped, opaque `r.*`
  hotspot reasons are filtered (`publicReason`), resolved-rule diffs show counts; an e2e test
  asserts no `r.<hex>` token reaches a report page.
- CI (`.github/workflows/site.yml`) gates PRs on Biome, `astro check`, Vitest, 4 Playwright
  specs and Lighthouse (a11y ≥ 0.95, perf ≥ 0.9) over a committed fixture; Pages deploys only
  from main/master and only after the downloaded snapshot bundle verifies (`store-verify`).
