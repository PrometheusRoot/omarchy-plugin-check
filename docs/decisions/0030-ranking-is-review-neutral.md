# 0030. Ranking is review-neutral

- Status: accepted
- Date: 2026-10-02
- Supersedes: part of 0029 (quality factor, unreviewed × 0.9 gate)

## Context

The first full snapshot ranked our three reviewed plugins #1–3, partly because reviewed plugins got a
real quality score and unreviewed ones a × 0.9 gate. We publish the ranking and also run a provider,
so letting our review coverage lift plugins is a conflict of interest.

## Decision

**No ranking factor or gate depends on provider review status. The quality factor is removed (weights
rebalanced to sum to 100: 22/16/11/11/8/8/8/11/5) and "unreviewed" gates at × 1.0. Verdicts only
demote: risky × 0.6, blocked never ranked or shelved.**

## Consequences

- Rank reflects public popularity and maintenance signals only; safety is shown next to it, not mixed in.
- Quality stays visible on the detail page; it just doesn't order shelves.
- `ranking-v1` factor list shrinks from 10 to 9; store reads `ranking.factors` from the snapshot.
