# 0029. Ranking: open factors and safety gates; star velocity from our own history

- Status: accepted
- Date: 2026-10-02
- Supersedes: —

## Context

The store's shelves need a ranking that is open (anyone can recompute it), cheap to collect for
~4,700 repositories, and never promotes unsafe plugins. The approved mockup fixed ten factors
with placeholder weights. Research (2026-10-02): GitHub no longer lists stargazers to non-owners
(GraphQL returns an empty `stargazers` connection, REST 404), so stars-over-time cannot be read.

## Decision

**Rank = (Σ weight × factor, each factor clamped to [0, 1]) × safety gate, with the mockup's ten
factors and weights (docs/RANKING.md); gates: blocked never ranked or shelved, risky × 0.6, no
trusted review × 0.9; star velocity (30 days) is measured from our own daily star-count history
(seeded from marketplace catalogs), contributors are distinct authors of the last 100 commits;
GitHub data comes from read-only GraphQL batches with the `gh` CLI token, cached per repository
and resumable.**

## Consequences

- Velocity is an estimate until 30 days of history exist (`velDays` says over how many days); the
  first snapshot extrapolates from the 2026-09-30 catalog.
- Unknown issue response and unknown quality score are neutral (0.5), not zero; unknown activity
  is zero. Built-in and retired plugins are not ranked.
- `rank.py` is pure and property-tested (ranks contiguous, scores within [0, 100], blocked never
  ranked or shelved, more stars never lower the score, gate order).
- Weights are placeholders until we have real usage data; changing them is a RANKING.md + ADR change.
