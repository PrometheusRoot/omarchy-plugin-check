# 0013. CLI verifies one signed snapshot, local-first

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Per-plugin network lookups leak what users install and depend on our uptime.

## Decision

**The CLI downloads one aggregator snapshot signed with the project ed25519 key, verifies it with `ssh-keygen -Y verify`, and answers lookups locally.**

## Consequences

- Compares installed HEAD + HEAD^{tree} with the report subject.
- A Sigstore "paranoid mode" (per-report verification) comes later.
