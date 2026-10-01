# 0015. Toolchain: uv, ruff, basedpyright, pytest + hypothesis; Biome; prek; just; Renovate

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

One tool per job, pinned, so humans, agents and CI run the same checks.

## Decision

**Python uses uv-compatible packaging, ruff (explicit select), basedpyright strict, pytest + hypothesis + mutmut; web uses Biome; hooks run via prek; `just` is the only command vocabulary; Renovate moves pins.**

## Consequences

- Rejected: mypy (slower, weaker inference), ty (not stable), ESLint+Prettier, Python pre-commit, Dependabot, Make.
- Staged strictness: legacy type errors live in a shrinking basedpyright baseline; package coverage floor ratchets up (docs/ENGINEERING.md#ratchets).
- Pins live in `standards/versions.toml`; `just docs` fails on drift.
