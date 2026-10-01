# 0011. Anti-oracle policy

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

A scanner that answers on demand is a free evasion-testing service.

## Decision

**No scan-on-demand: only marketplace-listed plugins are scanned, negative verdicts for new authors are delayed, rule ids stay opaque, some canary rules are undisclosed, and every rule change rescans everything.**

## Consequences

- Rate-limit verdict churn per plugin.
- `rulesVersion` (content hash of rules) changes trigger full rescans.
