# store — native Omarchy plugin app store

A standalone Quickshell app (its own process and floating 1280×800 window, ADR-0014) over the
signed client bundle of a snapshot (ADR-0032) plus an image cache. Approved design: the store mockup (tabs home /
search / browse / installed / status, hero carousel, shelves, detail sections, install
dialogs, ranking explainer). All-mono JetBrainsMono Nerd Font, zero radius, 1px borders,
colours from the current Omarchy theme.

## Run

```
just store-run              # bin/omarchy-plugin-store: qs -p store/, then float + size + center
just store-run --dev        # fake install runner, sample installed list, `t` cycles themes
qs -p store/                # plain Quickshell; Hyprland may tile the window
```

Bundle: `$OPC_STORE_BUNDLE` (a directory), else `~/.cache/omarchy-plugin-check/` (next to
`store.json`): `store-manifest.json(.sig)`, `store-home.json`, `store-search.json`,
`store-details.json`, `api/v1/plugins/`. `bin/omarchy-plugin-store-verify` checks the manifest
signature, kind, expiry and rollback and every file's sha256 before the app parses it (home
first, search columns after the first frame, each detail document when opened); a failure
refuses the bundle and the home tab says why. The DEV key is accepted only with `--dev` or
`OPC_STORE_DEV_KEYS=1`. Without any bundle the app uses the bundled dev data (`dev/`, a real
snapshot's bundle, gzipped, unpacked on first run, not verified; header chip says "dev").
Keybind suggestion: `super+shift+P` → `omarchy-plugin-store`.

Install runs `omarchy-plugin-check --add --pin <repo>` (argv, GitHub URLs only). Without the
checker on `PATH`, install is disabled with "checker not installed"; blocked plugins are always
refused. Remove runs `omarchy-plugin-remove <id> --yes` after a confirm.

The installed tab reads `omarchy-plugin-check status --json` (offline) when the checker is
installed: the listed id (also for a checkout at a former repository name, shown as *moved*),
commit and tree against the signed snapshot (`= reviewed · tree =`), and whether a reviewed
commit is newer (*update*) or HEAD is past the review (*roll back*). Both actions run
`omarchy-plugin-check pin --yes <id>` (argv, plain ids only) after the store's own confirm;
`omarchy plugin update` is never used for them (ADR-0035). Without the checker the tab falls back
to `git rev-parse HEAD` per plugin directory.

## Keys

`/` search · `1`–`5` tabs · `j k ↑ ↓ ← →` move · `⏎` open · `esc` back/close · `i` install
focused · `h l` hero slide · `?` ranking explainer · `t` theme (dev) · detail: `o s x d a`
sections · dialogs: `y` confirm. The map is `lib/nav.mjs` (tested).

## Layout

| Path | What |
|---|---|
| `shell.qml` | entry: `ShellRoot { StoreWindow {} }` |
| `ui/` | QML: layout and bindings only. Singletons `Theme`, `Store`, `Installer`, `ImageCache`; `worker.mjs` (WorkerScript) |
| `bin/` | `omarchy-plugin-store` launcher; `omarchy-plugin-store-verify` (bundle + detail verification, ADR-0032) |
| `lib/*.mjs` | pure logic, no Qt types (ADR-0031): `search` index + per-keystroke search over columns, `data` bundle adapter (the only file that knows snapshot fields), `rank`, `install` state machine + argv, `nav` key map + grid cursor, `theme` colors.toml → tokens, `format`, `imgcache`, `service` (worker protocol) |
| `lib/*.test.mjs` | `node --test store/lib` (`just store-test`), incl. the search latency benchmark |
| `SNAPSHOT-FIELDS.md` | every bundle field the UI reads |
| `dev/` | bundled dev data: the client bundle of a real DEV snapshot (4,777 plugins, 3 reviewed, real GitHub + marketplace stats) and the reviewed plugins' detail documents (`just store-dev-bundle DIR`) |
| `tools/` | `dev-bundle.sh`, `qmllint.sh` (`just store-lint`), `gen-qmldir.sh`, `coldstart.sh [--bench]`, `shot.sh` |

## Search

Built once in the worker, straight from the search columns (no per-plugin objects): one normalized haystack per plugin (name, author, tags, id,
description), field offsets, a name character mask, and one ordering per sort mode (sorted on
first use). A keystroke never sorts: one walk over the active ordering, one `indexOf` per
candidate and word, the hit position picks the score (name word-start 8 > name 6 > author 4 >
tag 3 > text 2 > fuzzy name subsequence 1), a counting sort over score buckets keeps ties in
sort order. Typing forward only revisits the previous matches; single characters are
pre-scored after the index, four per worker message so a keystroke never waits for all 36.

## Performance (dev laptop, i7-7560U powersave)

| What | Measured | Where |
|---|---|---|
| search, per keystroke | p95 ≈ 1 ms (node, best of 5), budget 5 ms | `just store-test` |
| search in the app (QV4 worker) | p50 ≈ 2 ms, p95 ≈ 12–20 ms (median 14); never blocks a frame | status tab, `coldstart.sh --bench` |
| empty Quickshell window, launch → first frame | ≈ 1.0 s | baseline |
| store, launch → first frame / home content (verified bundle) | median 1.5 s / 1.6 s (1.3–1.8 / 1.4–1.9) | `tools/coldstart.sh` |
| store, launch → searchable | median 2.3 s (2.0–2.8); was 4.0 s (3.1–5.9) with store.json | `tools/coldstart.sh` |
| verification (manifest sig + home sha256 / search + details sha256) | ≈ 0.1 s / ≈ 0.15 s of shell tools, the first overlapping Quickshell start-up | `omarchy-plugin-store-verify` |
| worker: parse / map / index, real 4,777-plugin search columns (1.6 MB) | ≈ 130 / 30 / 260 ms (after first frame); was 630 / 270 / 390 ms for store.json | status tab, `coldstart.sh` |

Measured 2026-10-02 as 8 interleaved before/after runs while another agent loaded the machine
(load 3–5 on 4 threads); absolute times are noisy, the ratios held in every pair.
