# opc-collector (collector/)

Public. Everything the store ranks by that is not a security verdict: the marketplace universe,
GitHub activity, marketplace engagement, and the ranking itself ([docs/RANKING.md](../docs/RANKING.md)).
Never imports the scanner, the orchestrator or the aggregator (ADR-0026); it exchanges files with
the aggregator (`stats.json`, `ranking.json` in; `api/v1/index.json` out).

```
opc-collect sync                                   # catalog.json + registry.json → cache (conditional GET)
opc-collect github [--batch 25] [--max-repos N] [--seed-catalog old-catalog.json] [--repo owner/name]...
opc-collect stats --out stats.json                 # GitHub stats + api.omarchyplugins.com engagement
opc-collect rank --stats stats.json --api-index api/v1/index.json --out ranking.json
```

Cache: `~/.cache/omarchy-plugin-check/collector/` (`marketplace/`, `github/<owner>__<name>.json`
with star history, `engagement.json`, `github-report.json`). A run skips repositories fetched within
`--ttl-hours` (20), so an interrupted or rate-limited run resumes; exit code 3 = stopped early.
`--repo` refreshes just those repositories now, whatever their age.

Weekly activity (`weeks`, the store's commit sparkline; shown, not ranked): commits per week for
52 weeks from the same last-100-commits page the contributor count uses; when that page is full,
weeks older than its oldest commit are `null` (unknown), not 0.

GitHub access: read-only GraphQL with the token of the `gh` CLI (`gh auth token`), read at run time,
kept in memory, sent only to api.github.com. Batches of 25 repositories (~1 point each), halved on
timeouts/502s, a pause between queries, and a wait (≤ `--max-wait`) or a clean stop when fewer than
100 points remain.

README images (store gallery): URLs only, pinned to the commit the README was read at
(`raw.githubusercontent.com/<o>/<r>/<sha>/...`), badges/SVGs dropped, at most 8 per repo or plugin
directory. Downloading is the store's job and off by default; plan: `~/.cache/omarchy-plugin-check/img/`
keyed by sha256(url), https only, `image/*` only, ≤ 5 MB, thumbnails generated on first view.

| Module | Role |
|---|---|
| `ports` / `net` | GraphQL + HTTPS ports; adapters (the only network/subprocess code) |
| `sync` | marketplace catalog/registry + engagement (conditional GET, cached) |
| `query` / `stats` / `readme` | GraphQL text; node → stats; README image URLs (pure) |
| `github` | resumable batch runner with cache and rate-limit budget |
| `inputs` / `rank` | join sources; ranking factors, gates, shelves (pure, property-tested) |
| `cli` | composition root |
