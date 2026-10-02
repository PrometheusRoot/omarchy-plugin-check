# store — native Omarchy plugin app store

A standalone Quickshell app (its own process and floating 1280×800 window, ADR-0014) over one
`store.json` snapshot plus an image cache. Approved design: the store mockup (tabs home /
search / browse / installed / status, hero carousel, shelves, detail sections, install
dialogs, ranking explainer). All-mono JetBrainsMono Nerd Font, zero radius, 1px borders,
colours from the current Omarchy theme.

## Run

```
just store-run              # bin/omarchy-plugin-store: qs -p store/, then float + size + center
just store-run --dev        # fake install runner, sample installed list, `t` cycles themes
qs -p store/                # plain Quickshell; Hyprland may tile the window
```

Snapshot: `$OPC_STORE_SNAPSHOT`, else `~/.cache/omarchy-plugin-check/store.json`, else the
bundled dev snapshot (`dev/store.json.gz`, unpacked on first run; header chip says "dev").
Keybind suggestion: `super+shift+P` → `omarchy-plugin-store`.

Install runs `omarchy-plugin-check --add --pin <repo>` (argv, GitHub URLs only). Without the
checker on `PATH`, install is disabled with "checker not installed"; blocked plugins are always
refused. Remove runs `omarchy-plugin-remove <id> --yes` after a confirm.

## Keys

`/` search · `1`–`5` tabs · `j k ↑ ↓ ← →` move · `⏎` open · `esc` back/close · `i` install
focused · `h l` hero slide · `?` ranking explainer · `t` theme (dev) · detail: `o s x d a`
sections · dialogs: `y` confirm. The map is `lib/nav.mjs` (tested).

## Layout

| Path | What |
|---|---|
| `shell.qml` | entry: `ShellRoot { StoreWindow {} }` |
| `ui/` | QML: layout and bindings only. Singletons `Theme`, `Store`, `Installer`, `ImageCache`; `worker.mjs` (WorkerScript) |
| `lib/*.mjs` | pure logic, no Qt types (ADR-0031): `search` index + per-keystroke search, `data` snapshot adapter (the only file that knows snapshot fields), `rank`, `install` state machine + argv, `nav` key map + grid cursor, `theme` colors.toml → tokens, `format`, `imgcache`, `service` (worker protocol) |
| `lib/*.test.mjs` | `node --test store/lib` (`just store-test`), incl. the search latency benchmark |
| `SNAPSHOT-FIELDS.md` | every snapshot field the UI reads, and proposed additions |
| `dev/` | dev snapshot (4,523 marketplace plugins; 3 reviewed; activity and engagement are sample values) |
| `tools/` | `dev-snapshot.mjs`, `qmllint.sh` (`just store-lint`), `gen-qmldir.sh`, `coldstart.sh`, `shot.sh` |

## Search

Built once in the worker: one normalized haystack per plugin (name, author, tags, id,
description), field offsets, a name character mask, and one ordering per sort mode (sorted on
first use). A keystroke never sorts: one walk over the active ordering, one `indexOf` per
candidate and word, the hit position picks the score (name word-start 8 > name 6 > author 4 >
tag 3 > text 2 > fuzzy name subsequence 1), a counting sort over score buckets keeps ties in
sort order. Typing forward only revisits the previous matches; single characters are
pre-scored after load.

## Performance (dev laptop, i7-7560U powersave)

| What | Measured | Where |
|---|---|---|
| search, per keystroke | p95 ≈ 1 ms (node, best of 5), budget 5 ms | `just store-test` |
| search in the app (QV4 worker) | p50 ≈ 2 ms, p95 ≈ 18 ms; never blocks a frame | status tab |
| empty Quickshell window, launch → first frame | ≈ 1.0 s | baseline |
| store, launch → first frame / home content (cached) | ≈ 1.4–1.9 s / ≈ 1.1–1.6 s | `tools/coldstart.sh` |
| worker: parse / map / index, real 4,772-plugin snapshot | ≈ 500 / 200 / 400 ms (after first frame) | status tab, `coldstart.sh` |
