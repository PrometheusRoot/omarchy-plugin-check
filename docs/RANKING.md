# Ranking and shelves

How the store orders plugins. Open by design: computed by the public collector
(`collector/opc_collector/rank.py`, `ranking-v2`) from public data, published in `store.json`
(`ranking.factors`, `ranking.gates`, per plugin `rank`, `score`, `fac[]`). Why: ADR-0029.
The ranking never decides safety; it only decides order. Safety comes from the providers (ADR-0009).

## Score

```
score = (Σ weight_f × clamp01(factor_f)) × gate(verdict)          0 ≤ score ≤ 100
```

| # | Factor (`id`) | Weight | factor ∈ [0, 1] | Source | Unknown → |
|---|---|---|---|---|---|
| 1 | log(stars) (`stars`) | 22 | log10(1 + stars) / log10(2100) | GitHub `stargazerCount` | 0 |
| 2 | ★ velocity 30d (`velocity`) | 16 | ln(1 + vel30) / ln(401) | our daily star history, see below | 0 |
| 3 | commit recency (`recency`) | 11 | exp(−days since last commit / 45) | last commit on the default branch | 0 |
| 4 | commits 90d (`commits`) | 11 | commits90 / 60 | default-branch `history(since: now−90d)` | 0 |
| 5 | contributors (`contrib`) | 8 | (authors − 1) / 5 | distinct authors of the last 100 commits | 0 |
| 6 | release cadence (`releases`) | 8 | releases in 180 days / 4 | GitHub releases (published) | 0 |
| 7 | issue response (`issues`) | 8 | 1 − ln(max(1, median h)) / ln(240) | median hours to the first non-author comment, last 20 issues | 0.5 |
| 8 | marketplace engagement (`engage`) | 11 | ln(1 + views) / ln(100001) | api.omarchyplugins.com/v1/stats `views` | 0 |
| 9 | marketplace verification (`verif`) | 5 | 1 if `verificationStatus = verified`, else 0.3 | catalog.json | 0.3 |

Weights sum to 100 (mockup placeholders, rebalanced without the quality factor). Every factor is clamped to [0, 1],
so no single signal (e.g. 50k stars) can outweigh the rest. Unknown issue response is neutral (a plugin is not punished for having no issues); unknown activity is 0.

**Review-neutral (ADR-0030).** No factor and no gate rewards being reviewed by a provider: we publish
this ranking and also run a provider, so review coverage must not move plugins up or down. Only the
safety gates below use verdicts, and only to demote.

**Star velocity.** GitHub no longer lists stargazers (with timestamps) to non-owners, so stars over
time cannot be read back. The collector keeps one star count per repository per UTC day (120 days,
in its cache; seeded from marketplace catalogs' `stars` at their `generatedAt`).
`vel30` = gain since the oldest point at most 30 days old, scaled to 30 days; `velDays` = the span
it was measured over (an estimate while < 30). Unstars count as zero gain.

**Bus factor** (shown, not ranked): the fewest authors who made half of the last 100 commits.

## Safety gates

| Combined verdict (trusted basis) | Gate |
|---|---|
| safe, caution | × 1.0 |
| no core/verified review yet ("unreviewed", incl. marketplace-only) | × 1.0 |
| risky | × 0.6 |
| blocked | not ranked, never on a shelf (still visible in search and installed) |

Built-in (`omarchy.*`) and retired plugins are not ranked. Ties: more stars, then id.

## Shelves (`store.json` `shelves`)

Only ranked plugins appear (so never blocked, retired or built-in).

| Shelf | Order | Size |
|---|---|---|
| `top` | rank | 50 |
| `trending` | `vel30` desc (only > 0), then rank | 50 |
| `new` | marketplace `listedAt` desc, then rank | 50 |
| `updated` | marketplace `repositoryUpdatedAt` desc, then rank | 50 |
| `safePicks` | combined `safe` on a trusted basis, by rank (later: 2+ providers) | 50 |
| `byCategory[<category>]` | rank within the marketplace category | 30 |

## Data collection (collector)

- Plugin universe: catalog.json + registry.json only (ADR-0010).
- GitHub: read-only GraphQL, 12 repositories per query (~0.25 points per repository; ≈1,200 points
  for the full catalog of the 5,000/hour budget), halving on timeouts/502s, a 1 s pause between
  queries, waiting for the reset (≤ 15 min) or stopping cleanly when < 100 points remain; per-repo
  cache so reruns resume. Token: `gh auth token` at run time, in memory only.
- Engagement: one conditional GET of the public stats endpoint per 20 hours.
