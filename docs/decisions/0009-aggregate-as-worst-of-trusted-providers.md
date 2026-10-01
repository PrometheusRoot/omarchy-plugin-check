# 0009. Aggregate as worst-of trusted providers

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Several providers may disagree; the combined verdict must not let one lenient provider hide another's warning.

## Decision

**Combined = worst-of core+verified providers; community and unsigned marketplace data cap at `caution`; `blocked` without file:line evidence is downgraded to `risky`; per-provider rows are always shown.**

## Consequences

- Merge logic is pure and shared (aggregator, CLI, store app) with golden-fixture contract tests.
- Disputes surface as a `contested` badge (v1).
