# 0014. Store app is a standalone, local-first Quickshell app

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Running inside omarchy-shell would put our UI in the lock-screen process; per-keystroke network calls are slow.

## Decision

**The store runs in its own Quickshell FloatingWindow over a single signed `store.json` plus an image cache, with all logic in pure `.js` modules and latency budgets enforced as tests.**

## Consequences

- `node --test` covers search/rank/state; QML holds layout and bindings only.
- Budgets: < 5 ms per keystroke over 4.5k entries, cold start < 300 ms.
