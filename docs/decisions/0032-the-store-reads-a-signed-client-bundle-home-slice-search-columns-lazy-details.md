# 0032. The store reads a signed client bundle: home slice, search columns, lazy details

- Status: accepted
- Date: 2026-10-02
- Supersedes: part of 0031 (the on-disk home cache)

## Context

ADR-0031 moved parsing off the GUI thread, but the store still parsed the whole 5.6 MB
`store.json` (≈ 4.8k objects) in QV4 before it was searchable, and only showed home content early
thanks to an unverified disk cache. The detail tabs also lacked our report data. Prior art: TUF
snapshot/targets metadata and Debian `Release` files sign one small index that lists the hash of
every other file, so one signature covers a consistent set of files fetched separately.

## Decision

**The aggregator also writes, from the same `store.json`, a client bundle — `store-home.json`
(shelves + only the rows they show), `store-search.json` (parallel columns, interned strings) and
`store-details.json` (sha256 per detail document) — committed to by one `store-manifest.json`
signed like the snapshot (`-n omarchy-plugin-check-snapshot`, distinguished by `kind`); the store
verifies the manifest (signature, kind, expiry, rollback) and every file's sha256 with
`store/bin/omarchy-plugin-store-verify` before parsing, maps home on the GUI thread, hands the
search columns to its worker after the first frame, and loads verified detail documents lazily;
`store.json` stays the CLI's contract unchanged.**

## Consequences

- One producer (`opc_aggregator.client`, pure, tested) and one verifier; JSON Schemas for all four
  files; `opc-aggregate client-bundle` re-projects an existing `store.json` (dev data).
- Detail documents now exist for every plugin of a snapshot and carry `listing` (full row incl.
  README gallery), `activity.weeks` (collector, from the last 100 commits; older weeks `null`)
  and each feed row's `detail.report` (the predicate's optional extension, rule ids opaque).
  store.json rows gain `verdict.criteria`, `verdict.risk`, `ini`, `accent`.
- The DEV key is accepted only with `OPC_STORE_DEV_KEYS=1` or `--dev`; a failed verification
  refuses the bundle (the home tab says why). The bundled dev data in `store/dev/` ships with the
  app and is not verified (it is as trusted as the QML next to it).
- The home disk cache is gone: the home slice is small enough (~140 KB) to read, verify and map
  on every start. Verification costs ~150 ms of shell tools on the dev laptop, overlapping
  Quickshell's own start-up.
- Measured (8 interleaved runs, dev laptop under load): worker parse + map 630 + 270 → 130 + 30 ms,
  index 390 → 260 ms, launch → searchable 4.0 → 2.3 s (medians); home content stays ≈ 1.6 s but
  is now verified; first frame 1.8 → 1.5 s. Desc in the columns is cut to 200 characters (full
  text in `listing.desc`).
- The single-character warm-up runs in chunks after the index, so a keystroke waits for at most
  one chunk.
