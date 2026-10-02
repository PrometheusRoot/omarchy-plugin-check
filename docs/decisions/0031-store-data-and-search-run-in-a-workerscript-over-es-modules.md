# 0031. Store data and search run in a WorkerScript over ES modules

- Status: accepted
- Date: 2026-10-02
- Supersedes: — (refines 0014's "pure `.js` modules" and its budgets)

## Context

Measured on the dev laptop (i7-7560U, powersave): Qt's QV4 runs the store's JS 10–40× slower
than V8; `JSON.parse` of the 5.6 MB `store.json` takes ~500 ms, mapping ~200 ms, the search index
~400 ms, and a common-word keystroke 5–30 ms. On the GUI thread that is seconds of frozen UI.
`WorkerScript` cannot `.import` `.pragma library` files, but it loads ES modules.
Quickshell itself needs ~1.0 s from launch to an empty window's first frame on this machine.

## Decision

**The store's logic lives in ES modules (`store/lib/*.mjs`, no Qt types) shared by QML, the
data `WorkerScript` (`ui/worker.mjs` → `lib/service.mjs`) and `node --test`; the worker owns
the snapshot, the adapter and the search index, and the UI holds only displayed records; the
home payload is cached on disk (`~/.cache/omarchy-plugin-check/store-home.json`) so the first
frame shows content and the snapshot is parsed after it.**

## Consequences

- No frame waits on parsing or searching; results carry a sequence number and stale ones are dropped.
- The ADR-0014 budgets are enforced where they are deterministic: search p95 < 5 ms per keystroke
  over 4.5k in `just store-test` (V8, best of five rounds). In-app numbers (QV4 worker) are shown
  on the status tab. Cold start is reported as launch → first frame and home content
  (`store/tools/coldstart.sh`); 300 ms is not reachable on top of Quickshell's ~1 s baseline here.
- Next lever if parse time matters: a client-oriented split of the snapshot (home slice + a
  columnar search file) produced by the aggregator, so QV4 parses strings and number arrays
  instead of 4.7k objects.
