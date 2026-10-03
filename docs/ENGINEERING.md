# Engineering standards

How code here is written, checked and changed. Why each rule exists lives in the
ADRs ([docs/decisions/](decisions/README.md)); module boundaries in
[ARCHITECTURE.md](ARCHITECTURE.md). This file is the reference.

## Principles

1. **Pure core, imperative shell.** Protocol, merge, ranking and display logic take data and return data; I/O sits behind ports (ADR-0004).
2. **One direction of dependencies,** enforced by import-linter (ARCHITECTURE.md "Import contracts").
3. **Every decision has a home:** why → ADR or an inline `# why:`; what → README/this file. Never both.
4. **Tests gate merges, not humans.** Core: 100% branch + property tests + mutation. Rest: coverage floor.
5. **Pinned everything:** tool versions (`standards/versions.toml`), action SHAs, container digests, lockfiles.

## Commands

`just` is the only vocabulary (humans, agents, CI). `just --list` shows all recipes.

| Recipe | Does | Gate |
|---|---|---|
| `just setup` | `.venv` with the public packages + pinned dev group (`pyproject.toml`); pinned binaries into `.tools/bin` | — |
| `just check` | lint, type, test, arch, docs | CI |
| `just lint` | prek hooks on all files (ruff, shfmt, shellcheck, actionlint, zizmor, schemas, docs) | CI, pre-commit |
| `just fmt` | ruff format + fix, shfmt | — |
| `just type` | basedpyright strict, no baseline | CI |
| `just test` | pytest + branch coverage + package floor | CI |
| `just arch` | import-linter contracts + deptry | CI |
| `just docs` | regenerate generated doc sections, fail if stale; recipe/pin/`why:` checks | CI, pre-commit |
| `just snapshot --out DIR --providers F` | collector + aggregator end to end → `api/v1/`, signed `store.json` | — |
| `just store-test` | `node --test store/lib`: store logic + search latency benchmark (p95 < 5 ms/keystroke over 4.5k) | before store changes |
| `just store-lint` | qmllint (filtered Quickshell false positives, each with a reason) + qmlformat check + `ui/qmldir` freshness | before store changes |
| `just store-run [--dev]` | run the store floating at 1280x800 (`--dev`: fake installer, sample installed list, `t` themes) | — |
| `just store-dev-bundle DIR` | refresh `store/dev/` (bundled dev data) from a snapshot build dir | after a snapshot schema change |
| `just plugin-test` | `bats plugin/tests` (temp HOME, fake `omarchy` + `git ls-remote`, per-test signing key) + `node --test plugin/lib` | before plugin changes |
| `just plugin-lint` | shellcheck (`enable=all`) + shfmt + qmllint (filtered, with reasons) + qmlformat + `omarchy plugin validate` | before plugin changes |
| `just site-dev` | `astro dev` over `OPC_API_DIR` (default: `.snapshot/api/v1`, a gitignored local snapshot build) | — |
| `just site-build` | static build into `site/dist` (+ api/v1, snapshot files, schemas, keys); prints time and size | — |
| `just site-lint` | Biome (`biome ci`) + `astro check` (strictest tsconfig) | CI (site.yml) |
| `just site-test` | Vitest (data shaping, compact index, query, row html) + 4 Playwright e2e over `site/tests/fixtures` | CI (site.yml) |

Three Python packages (ADR-0026); every recipe runs all of them: `spec/` (`opc_spec`, protocol +
schemas), `aggregator/` (`opc_aggregator`), `collector/` (`opc_collector`). They never import the
private scanner (import contracts); the scanner depends on `opc_spec` from a pinned commit of
this repository.

Python packaging is uv-compatible (PEP 735 `[dependency-groups]`): the dev tools are the `dev`
group of the root `pyproject.toml`; `just setup` uses plain `venv` + `pip --group` so uv is optional.

## Toolchain

<!-- BEGIN GENERATED: tools -->
| Stack | Tool | Version | Job | Status |
|---|---|---|---|---|
| python | uv | 0.12.21 | venv / lock / sync (optional; pip + .venv works) | active |
| python | ruff | 0.16.9 | format + lint + import sort | active |
| python | basedpyright | 1.40.1 | type check (strict, baseline for legacy) | active |
| python | pytest | 9.1.1 | tests | active |
| python | pytest-cov | 7.1.0 | branch coverage + floors | active |
| python | hypothesis | 6.168.3 | property tests (verdict invariants) | active |
| python | import-linter | 2.15 | architecture contracts | active |
| python | deptry | 0.25.1 | dependency hygiene | active |
| python | check-jsonschema | 0.38.2 | schema metaschema + workflow schema | active |
| python | mutmut | 3.8.0 | mutation testing of the core (nightly) | active |
| binaries | just | 1.58.0 | command runner | active |
| binaries | prek | 0.5.4 | git hooks (pre-commit compatible) | active |
| binaries | shfmt | 3.14.1 | shell format | active |
| binaries | actionlint | 1.7.12 | workflow lint | active |
| binaries | shellcheck | 0.11.0 | shell lint (also a scanner; pinned in tools.lock) | active |
| binaries | zizmor | 1.30.1 | workflow security audit (also a scanner) | active |
| binaries | hadolint | 2.14 | Dockerfile lint | planned |
| binaries | bats | 1.14.0 | shell tests (plugin CLI, plugin/tests/*.bats) | active |
| binaries | packer | 1.16.1 | P2 VM snapshot (validate + fmt offline; build needs the hcloud token) | active |
| qml | qmllint | 6.11 | store QML lint (system Qt; store/tools/qmllint.sh) | active |
| qml | qmlformat | 6.11 | store QML format check | active |
| qml | quickshell | 0.3.1 | store app runtime (system package) | active |
| web | node | 24 | QML/JS logic tests (node --test, store/), site | active |
| web | astro | 5.18.2 | static site (site/, ADR-0036); pinned in site/package.json + lockfile | active |
| web | typescript | 5.9.3 | astro check, strictest tsconfig (site/) | active |
| web | biome | 2.4.16 | format + lint (TS/Astro, site/) | active |
| web | vitest | 4.1.11 | unit tests (site/ data shaping + query) | active |
| web | playwright | 1.59.1 | 4 e2e specs (site/tests/e2e) | active |
| web | lhci | 0.15.1 | Lighthouse CI budgets: a11y >= 0.95, perf >= 0.9 | active |
<!-- END GENERATED: tools -->

## Python rules

- **ruff**: explicit `select` in `standards/ruff.toml` (never rely on defaults); complexity C901 ≤ 10;
  no parent-relative imports (`from opc_aggregator.x import y`).
- **Suppressions**: every `noqa`, `type: ignore`, `pyright: ignore`, `shellcheck disable` carries a
  trailing `# why: <reason>` on the same line (`just docs` greps for it).
- **basedpyright strict** everywhere, no baseline. It resolves imports from the `python` on `PATH`
  (`just` puts `.venv/bin` first; CI uses the setup-python interpreter), so no `venvPath` in config.
- **Docstrings** (Google style) state the contract — inputs, invariants, return — not the steps.
- **Tests**: unit tests per module; adapters behind ports (`Fetcher`, `Verifier`, `GraphQL`, `Http`)
  are replaced by fakes (no network). Property tests (hypothesis) pin the merge and ranking
  invariants. Hypothesis runs derandomized in PRs.

## QML / JS rules (store/)

- QML holds layout and bindings; logic lives in ES modules (`store/lib/*.mjs`, no Qt types) so
  QML, the data WorkerScript and `node --test` share one copy (ADR-0031).
- Every `ui/*.qml` sets `pragma ComponentBehavior: Bound`; delegates use `required` properties.
- `qmllint` must be clean apart from the filtered false positives listed (with reasons) in
  `store/tools/qmllint.sh`; `qmlformat` output is the format.
- Latency budgets are tests: the search benchmark and the search-file parse/index budget run in
  `just store-test`; cold start is measured with `store/tools/coldstart.sh [--bench]` (in-app
  search p50/p95 too) and shown on the store's status tab.
- Anything that becomes a process argument is validated in a pure module and passed as argv,
  never as shell text (`lib/install.mjs`, `lib/imgcache.mjs`).

## TS / Astro rules (site/)

- `astro/tsconfigs/strictest`; `astro check` must be clean. Biome is the formatter and linter
  (`site/biome.jsonc`; every disabled rule carries a `// why:`).
- Display logic lives in pure modules (`site/src/lib/*.ts`, no DOM, no I/O) shared by the build and
  the browser and unit-tested with Vitest; `data.ts` / `env.ts` are the only I/O. Pages and
  components only lay out.
- Every interpolated string in client HTML goes through `esc`. No rule ids, weights or score
  formulas on any page (ADR-0011).
- Budgets are CI gates: Lighthouse accessibility ≥ 0.95 and performance ≥ 0.9
  (`site/lighthouserc.json`), at most 4 Playwright specs, no horizontal scroll at 360 px.
- Versions are exact in `site/package.json` + `package-lock.json` and listed in
  `standards/versions.toml`; workflow actions are pinned by SHA.

## Bash rules (plugin/)

- Bash is glue only: logic over ~30 lines or any JSON parsing goes into a jq filter
  (`plugin/lib/*.jq`, pure, `include "opc"`) or a pure ES module, never into shell text.
- `shellcheck` runs with `enable=all` (`plugin/.shellcheckrc`); each disabled check carries its
  why there. `shfmt -i 2 -ci -bn -sr` is the format. `set -Eeuo pipefail`, `${braced}` variables,
  no `cond && cmd` as a statement (it can end a function with status 1 under `set -e`).
- Tests are bats (`plugin/tests/*.bats`) against a throwaway HOME with every XDG base dir inside
  it, a fake `omarchy` that records calls, a fake `git ls-remote`, and a snapshot signed with a
  key generated in the test; they never touch the real Omarchy config.
- Process arguments from data (plugin ids, paths, URLs) are validated in a pure function and
  passed as argv (`lib/panel.mjs`); git runs with `core.fsmonitor=false` inside plugin checkouts.
- jq filters run on jq 1.7 and 1.8 (CI's Ubuntu jq is 1.7, Omarchy ships 1.8): parenthesize
  the left side of every `... as $x` binding (`(a and b) as $x`: jq 1.7 binds only the last operand),
  and never take string offsets from `index`/`rindex`/`indices` (byte offsets before 1.8) —
  search `explode`d codepoints instead.

## Coverage targets

| Scope | Target | Enforced by |
|---|---|---|
| `opc_spec` (spec/) | 100% branch; basedpyright strict, no baseline | `just test`, `just type` |
| `opc_aggregator`, `opc_collector` | floor 90% (measured 99% / 100%); merge + rank property-tested; strict, no baseline | `just test`, `just type` |

Floors only move up; lowering one needs an ADR.

## How to

- **Change a schema:** update `schemas/CHANGELOG.md` (and spec/PROTOCOL.md for `spec/schemas`) plus
  an ADR in the same change; the report extension (`schemas/`) is shared with the private scanner,
  which vendors it at a pinned commit.
- **Add an ADR:** copy `docs/decisions/0000-template.md` to the next number, ≤ 1 page, run `just docs`.
- **Add a provider / client stack:** follow the planned rows in the tool table; reuse `standards/`.
- **Change the protocol, merge rules or ranking:** spec/PROTOCOL.md (+ `spec/schemas`, examples),
  docs/RANKING.md, an ADR; `just docs` refuses `merge.py`/`rank.py`/schema changes without one.
