# 0005. Stages are independent plugins behind one contract

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Scanners come and go; a missing or broken tool must reduce coverage visibly, not crash a scan.

## Decision

**One module per scanner exposing `NAME` and `run(ctx) -> StageResult` (`opsec.stage_api.Stage`); stages never import each other and use tools only via `ctx.runner`.**

## Consequences

- Missing tool => `skipped`, crash => `failed`; both recorded in `review.tools`.
- import-linter `independence` contract over `opsec.stages.*`; shared code goes to `stage_api`/`normalize`.
- Adding a scanner = one file + one `ORDER` entry + one fixture expectation + FakeRunner test.
