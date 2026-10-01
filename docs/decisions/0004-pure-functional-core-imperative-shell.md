# 0004. Pure functional core, imperative shell

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Verdict logic must be deterministic, replayable and testable without docker, network or clocks.

## Decision

**`verdict`, `score`, `normalize`, `capabilities`, `manifest`, `vocab` take data and return data; all I/O lives in the shell (`fetch`, `container`, `tools`, `stages`, `ai`, `report`, `cli`).**

## Consequences

- Enforced by import-linter (`core is pure`: no subprocess/os/shutil/socket/urllib, no container/tools/fetch/ai).
- Layer contract refines the proposal so each `|` group is truly independent: cli > fixtures > pipeline > {ai, stages, report, fetch, catalog, osvdb} > stage_api > {container, regexrules} > tools > {capabilities, normalize, verdict, inventory} > {score, manifest, schemas} > {vocab, options}.
- Core: 100% branch coverage, basedpyright strict with zero baseline entries, mutation-tested nightly.
