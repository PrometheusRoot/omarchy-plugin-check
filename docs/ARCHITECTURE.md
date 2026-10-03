# Architecture

Commit-bound safety + quality reviews for Omarchy plugins. Omarchy plugins are
Quickshell/QML that run **unsandboxed inside `omarchy-shell`** — the same process
as the lock screen, polkit agent, and notifications. `omarchy plugin add` clones
**mutable upstream HEAD**, and the marketplace binds installs to no reviewed commit.
So a review is only meaningful when it is pinned to a specific commit SHA and the
client can tell when the installed HEAD has drifted.

## Pipeline

```
[provider: our private scanner, or any other provider]                        (ADR-0007, ADR-0008)
   reviews marketplace-listed plugins at one commit → report.json (private format, optional
   redacted extension) → unsigned in-toto statements + feed index → the provider's data repo
[data repo CI]   cosign attest-blob --statement / sign-blob (keyless) → provider feed (ADR-0008)
[public: spec/ aggregator/ collector/]                                     (ADR-0026)
   opc-collect sync → github (GraphQL, resumable) → stats.json
   opc-aggregate build: registry → verify feeds → merge (worst-of) → api/v1/
   opc-collect rank (api/v1/index.json + stats.json) → ranking.json
   opc-aggregate build --stats --ranking --sign-key → store.json + .sig, store client bundle (ADR-0032):
                store-manifest.json + .sig → sha256 of store-home/-search/-details.json
[GitHub Pages]  Astro site + api/v1 + store.json + client bundle
[plugin]        omarchy-plugin-check CLI / menu / QML panel  ← verifies store.json (ssh-keygen -Y)
[store]         store app  ← verifies store-manifest.json (ssh-keygen -Y) + sha256 of each file
```

Our own provider (`opc`) is a private scanner (ADR-0007): static scanners are ground truth and an
isolated, read-only AI reviewer may only escalate (ADR-0003). It runs on short-lived, single-use
machines that hold no long-lived secrets. Its rules, weights, prompts, fixtures and runner
configuration are deliberately not published (ADR-0011); what it publishes is the coarse,
signed statement described in spec/PROTOCOL.md.

## Repositories

The project is split (ADR-0007, ADR-0026); this is the public tool:

| Repo | Visibility | Content |
|---|---|---|
| `omarchy-plugin-check` | public | `spec/ aggregator/ collector/ schemas/ standards/` + site, plugin, store, docs |
| `omarchy-plugin-check-scanner` | private | `scanner/ orchestrator/` (stages, rules, prompts, weights, fixtures) |
| `omarchy-plugin-check-data` | public | our provider feed (`opc`), signed in its GitHub Actions |
| `omarchy-plugin-check-plugin` | public | mirror of `plugin/` for `omarchy plugin add` |

## Static API (aggregator → Pages; spec/schemas/api-*.schema.json)

| Path | Schema | Notes |
|---|---|---|
| `api/v1/meta.json` | api-meta | registry, providers (feed version/expiry/status), counts, rejected rows |
| `api/v1/index.json` | api-index | one row per plugin: combined verdict, basis, contested, per-provider verdicts |
| `api/v1/by-repo.json` | api-by-repo | repo key (incl. previous names) → plugin ids |
| `api/v1/plugins/<id>.json` | api-plugin | per-provider rows + combined (ADR-0009, ADR-0027; `combined.tree` ADR-0034); in a snapshot build one per plugin, with `listing` (full store row), `activity.weeks` and our row's `detail.report` (ADR-0032) |
| `api/v1/plugins/<id>/<provider>/<sha>.json` | statement | the verified in-toto statement (immutable) |
| `store.json` (+ `.sig`) | store | compact snapshot, the CLI's contract (ADR-0013, ADR-0028); rows carry `verdict.commit`/`verdict.tree` and `formerRepos` (ADR-0034) |
| `store-manifest.json` (+ `.sig`) | store-manifest | the store app's one signed file: version, expiry, sha256 + size of the files below (ADR-0032) |
| `store-home.json` | store-home | first frame: shelves + only the rows they show (~140 KB) |
| `store-search.json` | store-search | every plugin as parallel columns, strings interned (~1.6 MB) |
| `store-details.json` | store-details | plugin id → sha256 of its `api/v1/plugins/<id>.json` |

The provider's own report (schemas/report.schema.json) is the optional `predicate.report`
extension; `schemas/{index,meta,by-repo,plugin-latest}.schema.json` describe the provider-internal
layout and are superseded for the public API.

## Data flow: one review (provider side, outcome level)

0. The plugin is resolved in the marketplace catalog (source of truth for id, name, metadata,
   `manifestPath`; follows registry repositoryMigrations). Unknown URL → `unlisted`, never scanned;
   built-in `omarchy.*` → not scanned in v1 (ADR-0010).
1. The repository is fetched at one commit (marketplace-verified, listing or upstream-observed;
   recorded as `review.scanTarget`) in an isolated environment; monorepo plugins are reviewed at
   their `manifestPath` only.
2. Static scanners run on the checkout; their findings are ground truth.
3. An AI reviewer may add findings and raise the outcome by one level; it can never lower an
   outcome, reach `blocked`, or un-block (ADR-0003). Its output is discarded if any integrity check
   fails.
4. The outcome (`safe | caution | risky | blocked`) and criteria are computed (docs/VERDICT-LOGIC.md),
   the report is schema-validated, and the provider publishes a coarse statement: categories,
   severities and file:line evidence, never internal rule ids, weights or formulas.

## Public packages (`spec/`, `aggregator/`, `collector/`)

Public-bound (ADR-0007, ADR-0026): they never import the private scanner (`opsec`, `opsec_orch`); the aggregator and the
collector never import each other and exchange files only. `opc_spec` (bottom): protocol
vocabulary, identifiers, marketplace identity, typed JSON accessors, schema validation.
`opc_aggregator`: ports `Fetcher`/`Verifier` (adapters: HTTPS/local, `SigstoreVerifier` — the only
`sigstore` import —, `UnsignedDevVerifier`), pure `admit`/`merge`/`api`/`snapshot`, `sshsig`
(`ssh-keygen -Y`). `opc_collector`: ports `GraphQL`/`Http` (adapters in `net`, the only network and
subprocess code), pure `query`/`stats`/`readme`/`rank`. Protocol: spec/PROTOCOL.md; ranking:
docs/RANKING.md.

<!-- BEGIN GENERATED: public-contracts -->
**spec imports no other package of this repo** (forbidden)

- `opc_spec`
- may not import: `opsec`, `opsec_orch`, `opc_aggregator`, `opc_collector`

**spec is pure (no network, no processes)** (forbidden)

- `opc_spec.vocab`, `opc_spec.ids`, `opc_spec.marketplace`, `opc_spec.jsonv`
- may not import: `subprocess`, `socket`, `urllib`, `http`, `os`, `shutil`

**aggregator layers** (layers)

1. `opc_aggregator.cli`
2. `opc_aggregator.publish`
3. `opc_aggregator.build`
4. `opc_aggregator.fetch | opc_aggregator.sigstore_verifier | opc_aggregator.unsigned | opc_aggregator.sshsig | opc_aggregator.state`
5. `opc_aggregator.api | opc_aggregator.snapshot | opc_aggregator.statements | opc_aggregator.client`
6. `opc_aggregator.admit | opc_aggregator.merge`
7. `opc_aggregator.marketplace`
8. `opc_aggregator.ports`
9. `opc_aggregator.model`

**public packages never import the private scanner or orchestrator** (forbidden)

- `opc_aggregator`
- may not import: `opsec`, `opsec_orch`, `opc_collector`

**sigstore only behind the Verifier port** (forbidden)

- `opc_aggregator.build`, `opc_aggregator.publish`, `opc_aggregator.api`, `opc_aggregator.snapshot`, `opc_aggregator.statements`, `opc_aggregator.admit`, `opc_aggregator.merge`, `opc_aggregator.marketplace`, `opc_aggregator.model`, `opc_aggregator.ports`, `opc_aggregator.unsigned`, `opc_aggregator.fetch`, `opc_aggregator.state`, `opc_aggregator.sshsig`
- may not import: `sigstore`

**aggregator core is pure** (forbidden)

- `opc_aggregator.admit`, `opc_aggregator.merge`, `opc_aggregator.marketplace`, `opc_aggregator.model`, `opc_aggregator.ports`, `opc_aggregator.api`, `opc_aggregator.snapshot`, `opc_aggregator.statements`
- may not import: `subprocess`, `socket`, `urllib`, `http`, `shutil`, `sigstore`, `opc_aggregator.fetch`, `opc_aggregator.sshsig`

**collector layers** (layers)

1. `opc_collector.cli`
2. `opc_collector.github | opc_collector.sync | opc_collector.net`
3. `opc_collector.inputs`
4. `opc_collector.rank | opc_collector.query | opc_collector.stats`
5. `opc_collector.readme | opc_collector.ports`

**public packages never import the private scanner or orchestrator** (forbidden)

- `opc_collector`
- may not import: `opsec`, `opsec_orch`, `opc_aggregator`

**only net talks to the network or runs processes** (forbidden)

- `opc_collector.cli`, `opc_collector.github`, `opc_collector.sync`, `opc_collector.inputs`, `opc_collector.rank`, `opc_collector.query`, `opc_collector.stats`, `opc_collector.readme`, `opc_collector.ports`
- may not import: `http`, `socket`, `subprocess`

**urllib (requests) only in net; readme may parse URLs** (forbidden)

- `opc_collector.cli`, `opc_collector.github`, `opc_collector.sync`, `opc_collector.inputs`, `opc_collector.rank`, `opc_collector.query`, `opc_collector.stats`, `opc_collector.ports`
- may not import: `urllib`

**ranking core is pure** (forbidden)

- `opc_collector.rank`, `opc_collector.query`, `opc_collector.stats`, `opc_collector.readme`, `opc_collector.inputs`
- may not import: `os`, `shutil`, `time`, `pathlib`, `opc_collector.net`, `opc_collector.github`, `opc_collector.sync`
<!-- END GENERATED: public-contracts -->

## Store app (`store/`)

A standalone Quickshell app (ADR-0014): its own process and floating window, never inside
`omarchy-shell`. Reads the client bundle (ADR-0032): a signed manifest, the home slice, the
search columns and lazily one aggregated view per plugin; no network per keystroke.

```
qs -p store/ ── StoreWindow (GUI thread: layout + bindings only)
                 ├─ Theme      ~/.local/state/omarchy/current/theme/colors.toml → tokens (lib/theme.mjs)
                 ├─ Store      bin/omarchy-plugin-store-verify (Process) → FileView(store-home.json)
                 │               → data.mjs fromHome (GUI thread) · after the first frame
                 │               FileView(store-search.json) ─► WorkerScript ui/worker.mjs
                 │               lib/service.mjs: data.mjs columns · search.mjs index · rank.mjs
                 │             ◄─ records for what is on screen; details: verifier → fromDetail
                 ├─ Installer  omarchy-plugin-check --add --pin <repo> | pin --yes <id> (argv) · lib/install.mjs
                 │               installed tab ← omarchy-plugin-check status --json (offline)
                 └─ ImageCache curl → ~/.cache/omarchy-plugin-check/img/ (https only, 4 at a time)
```

- **One adapter.** `lib/data.mjs` is the only code that knows snapshot field names
  (store/SNAPSHOT-FIELDS.md); the UI model is stable across schema changes.
- **Pure logic in ES modules** (`lib/*.mjs`, no Qt types), shared by QML, the worker and
  `node --test` (ADR-0031). QML holds layout and bindings.
- **Safety in the UI:** blocked plugins never reach shelves or the hero and their install is
  refused; install argv only accepts a plain GitHub URL; remove needs a confirm.

## Site (`site/`)

Astro 5, static output, deployed to GitHub Pages under `OPC_SITE_BASE` (ADR-0036).

```
api/v1/ (OPC_API_DIR) ── src/lib/data.ts (build-time fs, memoised) ──► pages/plugins/[id] (one per plugin)
        │                      └─ lib/compact.ts encodeIndex ──► data/plugins.json ──► client/index.ts
        │                                                          (decode · lib/query.ts · lib/render.ts)
        └─ integration opc-static-api (astro:build:done) ──► dist/api/v1, dist/store*.json(.sig),
                                                             dist/spec/v1/*.schema.json, dist/keys/
```

- **Pure core** in `src/lib/` (`model`, `compact`, `query`, `render`): data in, strings out, no DOM,
  shared by the build and the browser; `data.ts` and `env.ts` are the only I/O.
- **Pages**: `/` (index, first 50 rows server-rendered), `/plugins/<id>/` (combined verdict, every
  provider row, one panel per provider: section nav · sections · aside), `/providers/`, `/about/`,
  `/api/`; `404` doubles as the *unlisted* state for unknown plugin ids.
- **Anti-oracle** (ADR-0011): rule ids and opaque `r.*` reasons never reach a page.

## Trust model (one line)

Scanners are ground truth and can hard-fail to `blocked`. The AI is **escalate-only**:
it may add findings and raise the outcome one level, never lower it, never reach
`blocked`, and never un-block. See docs/THREAT-MODEL.md.

## Checker plugin (`plugin/`)

The public mirror repo root (`omarchy plugin add`-able; `omarchy plugin validate` clean). One
CLI, one panel, one bar widget; every decision is a pure jq filter or ES module (ADR-0033).

```
bin/omarchy-plugin-check (bash glue)                           ~/.cache/omarchy-plugin-check/
  update ── store-manifest.json(.sig) ─ ssh-keygen -Y verify ─ sha256 of each listed file ──►
            store.json · store-details.json · store-home/search.json (store app) · meta.json · index.json
            (keys/allowed_signers; dev key only with OPC_DEV_KEYS)   ~/.local/state/…/state.json +
            store-bundle-version (anti-rollback, shared with the store); bare store.json(.sig) also accepted
  <url|id> ─ lib/index.jq · opc.jq resolve ─ git ls-remote ─ lib/model.jq ─ lib/card.jq
  --add ──── same model ─ gate (refuse 2 | confirm | proceed) ─ omarchy plugin add ─ pin + verify
             HEAD and HEAD^{tree} ─ omarchy plugin validate / enable ─ lib/changes.jq (CHANGES.md)
  status ─── plugin checkouts (id + origin + HEAD + tree) ─ lib/status.jq ─► status.json ─ lib/table.jq
  pin <id> ─ status entry ─ git fetch <listed repo> ─ lib/pin.jq (direction, files, verdict change)
             ─ confirm ─ checkout --detach + verify commit/tree ─ validate ─ rescanPlugins ─ CHANGES.md
  setup ──── ~/.local/bin link · lib/menu.jq ─► extensions/omarchy-menu.jsonc (marked block)
omarchy-shell: BarWidget.qml (shield, worst state) ──toggle──► Panel.qml (rows, rescan = status --json)
               both read status.json through a watched FileView (no polling); logic in lib/panel.mjs
```

- **Identity** follows the marketplace (ADR-0010): an installed plugin matches a listing only
  when its id and its `origin` repository match (the listed repository or one of its
  `formerRepos`, then flagged moved, ADR-0034); anything else is `unlisted`.
- **What is trusted**: the signed snapshot (combined verdict, providers, reviewed commit and
  tree, criteria, risk) and detail documents whose sha256 the signed `store-details.json` lists
  (findings).
- **States** (worst last): safe, caution, unreviewed, unlisted, stale, retired, risky, blocked.

## Phase status

P3 protocol, aggregator, collector, signed snapshot (local dev run done; data repo + Pages pending) ·
P4 site (static Astro build done; Pages deploy pending a published snapshot) · P5 checker plugin
(CLI + panel + bar widget, done; mirror repo pending) · P5b store app (v1 UI + engine, done) ·
P6 scheduling · P7 scale/search/dynamic. The scanner phases (P0–P2) live in the private repository.
