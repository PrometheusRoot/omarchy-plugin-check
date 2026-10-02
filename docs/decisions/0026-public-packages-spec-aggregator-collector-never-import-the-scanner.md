# 0026. Public packages (spec, aggregator, collector) never import the scanner

- Status: accepted
- Date: 2026-10-02
- Supersedes: — (implements 0007 for the P3 code)

## Context

ADR-0007 splits the project into a public tool and a private scanner, but both live in this
monorepo until the history split. P3 adds the first public code (protocol, aggregation, ranking);
if it imported `opsec` even once, the public repo could not be cut out without the scanner, and
rule ids or weights could leak through shared helpers.

## Decision

**`spec/` (`opc_spec`), `aggregator/` (`opc_aggregator`) and `collector/` (`opc_collector`) are
separate public distributions with their own pyproject, tests and import contracts; none may
import `opsec`, `opsec_orch` or each other except `opc_spec` (the bottom); aggregator and
collector exchange only documented JSON files (`stats.json`, `ranking.json`, `api/v1/index.json`);
the scanner may use `opc_spec` (optional extra `opsec[attest]`), never the reverse.**

## Consequences

- Enforced by import-linter `forbidden` contracts in each public pyproject (`just arch`), by
  deptry (no undeclared dependency on `opsec`), and by each package installing and testing alone.
- Shared marketplace identity (catalog + registry → plugins, states, migrations) and typed JSON
  accessors moved into `opc_spec` so the collector does not need the aggregator.
- The scanner's only public-facing output is `opsec attest`/`opsec feed`: coarse statements without
  rule ids, scores or weights (tested). The full report is an opt-in, redacted extension.
- The history split (ADR-0007) moves `spec aggregator collector schemas standards` to the public
  repo unchanged; `scanner orchestrator` stay private.
