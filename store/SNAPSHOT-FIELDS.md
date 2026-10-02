# Snapshot fields the store reads

The store reads the **client bundle** (ADR-0032; spec/PROTOCOL.md §7), never `store.json`
itself (that stays the CLI's contract):

| File | Read | Schema |
|---|---|---|
| `store-manifest.json` + `.sig` | by `bin/omarchy-plugin-store-verify` before anything else | store-manifest |
| `store-home.json` | GUI thread, first frame (`Data.fromHome`) | store-home |
| `store-search.json` | worker, after the first frame (`Data.fromSearch`, `Data.record`) | store-search |
| `store-details.json` | by the verifier, per detail open | store-details |
| `apiBase` + `plugins/<id>.json` | lazily, verified (`Data.fromDetail`) | api-plugin |

Every field below is mapped in **one file, `lib/data.mjs`**; QML and the other libs only see
the UI model it returns. A schema change is a `data.mjs` change (plus its test).
Missing optional fields degrade (shown as `—`, initials tile, "no data"), never break.

## store-home.json

Envelope (same values as store.json):

| Field | Used for |
|---|---|
| `version`, `generatedAt`, `expires` | snapshot age chip, status tab |
| `dev` | yellow "dev" chip (DEV key) |
| `catalog.generatedAt`, `catalog.plugins` | status tab, footer |
| `imageBase` | prefix for relative `img.thumb` / `img.full` / `thumb` |
| `apiBase` | detail documents (relative = next to the bundle, `https://` = fetched by the verifier into `~/.cache/omarchy-plugin-check/api/`) |
| `providers[]` `{id, name, tier, verification, rows}` | provider lines, status tab, tier chips |
| `ranking.factors[]` `{id, label, weight}`, `ranking.gates`, `ranking.version` | "why #N" bars and the explainer |
| `categories[]` `{name, count}` | category tiles and chips |
| `counts {safe, caution, risky, blocked, unknown, images}`, `total` | status tab, footer |
| `shelves.{top, trending, new, updated, safePicks}`, `shelves.byCategory[cat]` (12 ids each) | home and browse shelves; hero = first 6 of `top` with an image; "similar" |
| `plugins[]` | the rows those shelves show, in store.json row format (below), without `gallery` |

Blocked plugins are dropped from every shelf and the hero by the adapter, whatever the
snapshot says (store approval note); they stay in search and installed.

## Plugin rows (home `plugins[]`, detail `listing`; store.json row format)

| Field | Used for |
|---|---|
| `id`, `name` | identity, title |
| `ini`, `accent` | initials tile and accent (else derived from the name / id hash) |
| `author`, `tags[]`, `desc` | cards, rows |
| `cat`, `kind` | chips, filters, browse |
| `repo` | install argv (`omarchy-plugin-check --add --pin <repo>`, must be `https://github.com/o/r`), repo link |
| `license`, `version`, `verif` | detail header; `verif` also a ranking factor label |
| `state` | detail aside |
| `listed`, `updated` (else `gh.lastCommit`) | "new"/"updated" sorts, ages |
| `img.thumb`, `img.full` | card thumbnail, hero and first gallery image |
| `gallery[]` (detail `listing` only) | README images after the marketplace preview |
| `gh.stars`, `gh.vel30` | cards, sorts (`★`, trending) |
| `gh.c90`, `gh.contrib`, `gh.bus`, `gh.rel180`, `gh.lastRelease`, `gh.respH` | activity stats, ranking explainer |
| `mkt.views`, `mkt.copies`, `mkt.hearts` | marketplace box |
| `rank`, `score`, `fac[]` | rank badges, rank sort, "why #N" (same order as `ranking.factors`) |
| `verdict.combined` | outcome glyph/colour everywhere (`unknown` → shown as **unreviewed**) |
| `verdict.basis`, `verdict.contested`, `verdict.commit` | detail; installed-vs-reviewed comparison |
| `verdict.providers{id: verdict}` | provider line on hero / installed rows |
| `verdict.criteria {checked[], failed[]}` | criteria chips on hero/cards without the detail document |
| `verdict.risk` (0–100) | "caution 13/100" and the meter |
| `report` | `true` → a detail document `plugins/<id>.json` exists |

## store-search.json (columns)

Row `i` of every column is one plugin. The worker keeps the arrays as they are and resolves
`author`, `cat`, `kind` and `verdict` indices into string columns once; `Data.record(t, i)`
builds a UI record only for rows on screen (`complete: false`: no license, gallery, `gh`
details or `fac` — opening the detail, or the ranking explainer, completes it from `listing`).

| Column | Record field |
|---|---|
| `id`, `name`, `tags` (space-joined), `desc` (≤ 200 chars) | same; search haystack |
| `author`, `cat`, `kind`, `verif`, `accent` (indices into `dict`) | same |
| `verdict`, `basis` (indices into `dict.verdict` / `dict.basis`) | `verdict` (`unknown` → unreviewed), `basis` |
| `flags` (1 contested, 2 archived, 4 not installable, 8 custom install, 16 retired, 32 builtin, 64 detail) | `contested`, `archived`, `listingState`, `report` |
| `rank`, `score`, `stars`, `vel30`, `listed`, `updated` | same (`score` → `rankScore`); sorts |
| `thumb` | `thumb`, `full` |
| `repo` (`owner/name` for GitHub) | `repo` (`https://github.com/` + it) |
| `commit`, `risk`, `critC`/`critF` (bitmasks over `dict.criteria`), `prov[k]` (per `dict.providers`) | `commit`, `risk`, `criteria`, `providers` |
| `ini` | `ini` (`""` → derived) |

## Detail document (`apiBase` + `plugins/<id>.json`)

| Field | Used for |
|---|---|
| `listing` | completes the record (header, marketplace box, activity stats, explainer, gallery) |
| `activity.weeks[52]` | the commits sparkline (`null` = unknown, older than the last 100 commits) |
| `combined {verdict, basis, contested, commits, reasons}` | security tab |
| `providers[] {provider, tier, verification, verdict, effectiveVerdict, adjustments, counted, timeReviewed, commit, summary, criteria{checked, failed, notChecked}, findings[]}` | provider rows, criteria chips, evidence table (counted rows' `findings`) |
| a feed row's `detail.report` (predicate `report` extension, rule ids opaque) | tech/deps/security tabs: AI summary, capability levels, system areas, network hosts, performance, dependencies + advisories, code quality, maintenance, verdict score/reasons/criteria, hard fails; falls back to the evidence above when absent |

## Local state (not in the snapshot)

| Source | Used for |
|---|---|
| `omarchy-plugin-check status --json` (when the checker is installed) | installed list keyed by listed id: `state`, `commitMatch`, `treeMatch`, `moved`, `repin` (update / roll back), `reviewed.commit` (`Data.parseInstalled`, `Inst.statusState`); the checker reads `verdict.commit`, `verdict.tree` and `formerRepos` from store.json, so the store needs neither in its bundle columns |
| `~/.config/omarchy/plugins/*/` + `git rev-parse HEAD` | fallback without the checker: installed list and installed-vs-reviewed commit |
| `command -v omarchy-plugin-check` | install enabled / "checker not installed" |
| `~/.local/state/omarchy/current/theme/colors.toml` | theme tokens (lib/theme.mjs) |
| `~/.local/state/omarchy-plugin-check/store-bundle-version` | last accepted bundle version (rollback check) |
| `~/.cache/omarchy-plugin-check/img/`, `api/` | image cache; detail documents fetched from an https `apiBase` |
