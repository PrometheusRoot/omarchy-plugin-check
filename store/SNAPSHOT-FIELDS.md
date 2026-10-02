# Snapshot fields the store reads

The store reads `store.json` (spec/schemas/store.schema.json, v1 draft) and, lazily, one
aggregated view per plugin (`apiBase` + plugin `report`, spec/schemas/api-plugin.schema.json).
Every field below is mapped in **one file, `lib/data.mjs`**; QML and the other libs only see
the UI model it returns. A schema change is a `data.mjs` change (plus its test).

Missing optional fields degrade (shown as `—`, initials tile, "no data"), never break.

## store.json, top level

| Field | Used for |
|---|---|
| `version`, `generatedAt`, `expires` | snapshot age chip, status tab |
| `dev` | yellow "dev" chip; "sample values" notes |
| `catalog.generatedAt`, `catalog.plugins` | status tab, footer |
| `imageBase` | prefix for relative `img.thumb` / `img.full` |
| `apiBase` | detail view location (relative = next to `store.json`, `https://` = fetched with curl into `~/.cache/omarchy-plugin-check/api/`) |
| `providers[]` `{id, name, tier, verification, rows}` | provider lines, status tab, tier chips |
| `ranking.factors[]` `{id, label, weight}`, `ranking.gates`, `ranking.version` | "why #N" bars and the explainer (labels/weights come from here, not from the store) |
| `shelves.{top, trending, new, updated, safePicks}` (ids) | home shelves (first 12); hero = first 6 of `top` with an image |
| `shelves.byCategory[cat]` (ids) | browse shelves, "similar" |
| `categories[]` `{name, count}` | category tiles and chips |
| `plugins[]` | everything else, below |

Blocked plugins are dropped from every shelf and the hero by the adapter, whatever the
snapshot says (store approval note); they stay in search and installed.

## store.json, `plugins[]`

| Field | Used for |
|---|---|
| `id`, `name` | identity, title, search (name scores highest) |
| `author`, `tags[]`, `desc` | cards, rows, search haystack |
| `cat`, `kind` | chips, filters, browse |
| `repo` | install argv (`omarchy-plugin-check --add --pin <repo>`, must be `https://github.com/o/r`), repo link |
| `license`, `version`, `verif` | detail header; `verif` also a ranking factor label |
| `state` | detail aside |
| `listed`, `updated` (else `gh.lastCommit`) | "new"/"updated" sorts, ages |
| `img.thumb`, `img.full` | card thumbnail, hero and gallery image |
| `gh.stars`, `gh.vel30` | cards, sorts (`★`, trending) |
| `gh.c90`, `gh.contrib`, `gh.bus`, `gh.rel180`, `gh.lastRelease`, `gh.respH` | activity stats |
| `mkt.views`, `mkt.copies`, `mkt.hearts` | marketplace box |
| `rank`, `score`, `fac[]` | rank badges, rank sort, "why #N" (same order as `ranking.factors`) |
| `verdict.combined` | outcome glyph/colour everywhere (`unknown` → shown as **unreviewed**) |
| `verdict.basis`, `verdict.contested`, `verdict.commit` | detail; installed-vs-reviewed comparison |
| `verdict.providers{id: verdict}` | provider line on hero / installed rows |
| `report` | `true` → `plugins/<id>.json`; a string → that path; absent → no detail fetch |

### Proposed optional additions (the UI already reads them; absent today = degrade)

| Field | Why |
|---|---|
| `verdict.criteria {checked[], failed[]}` | criteria chips on hero/cards without fetching the detail view |
| `verdict.risk` (0–100, trusted provider's risk score) | "caution 37/100" and the meter |
| `ini`, `accent` | marketplace initials tile and accent (else derived from the name / id hash) |

## Detail view (`apiBase` + `report`)

| Field | Used for |
|---|---|
| `combined {verdict, basis, contested, commits, reasons}` | security tab |
| `providers[] {provider, tier, verification, verdict, effectiveVerdict, adjustments, counted, timeReviewed, commit, summary, criteria, findings[]}` | provider rows, criteria chips, evidence table (counted rows' `findings`: `severity`, `confidence`, `message`, `locations[0].path:startLine`) |
| `activity.weeks[52]` *(proposed)* | the commits sparkline |
| our row's `detail.report` *(proposed; the dev snapshot carries it)* | tech/deps tabs: AI summary, capability levels, system areas, network hosts, performance, dependencies + advisories, quality, maintenance; falls back to the evidence above when absent |

## Local state (not in the snapshot)

| Source | Used for |
|---|---|
| `~/.config/omarchy/plugins/*/` + `git rev-parse HEAD` | installed list and installed-vs-reviewed state |
| `command -v omarchy-plugin-check` | install enabled / "checker not installed" |
| `~/.local/state/omarchy/current/theme/colors.toml` | theme tokens (lib/theme.mjs) |
| `~/.cache/omarchy-plugin-check/img/`, `store-home.json` | image cache, home payload for the next cold start |
