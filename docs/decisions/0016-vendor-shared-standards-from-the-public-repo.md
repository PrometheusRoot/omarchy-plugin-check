# 0016. Vendor shared standards from the public repo

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Two repos (public tool, private scanner) must not drift in lint, type or hook rules.

## Decision

**`standards/` in the public repo is the single source; the private repo vendors it at a pinned tag, CI verifies the vendored hash, and reusable workflows are referenced by SHA.**

## Consequences

- Changes go upstream first; the private repo never edits `standards/`.
- Configs consume it via `extend`/`extends`.
