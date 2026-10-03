# omarchy-plugin-check

Commit-bound safety and quality reviews for Omarchy plugins — the open tool.

Omarchy plugins (Quickshell/QML) run **unsandboxed inside `omarchy-shell`**, and
`omarchy plugin add` clones **mutable upstream HEAD** — so a review only means something
when it is pinned to a commit and the client can tell when the installed HEAD has drifted.
Review providers publish signed, commit-bound verdicts (`safe | caution | risky | blocked`);
this repository verifies and merges them, ranks plugins, and ships the website, the store app
and the checker plugin that gates installs.

Our own provider's scanner is closed on purpose: publishing detection rules and weights would let
attackers test evasions offline (ADR-0007, ADR-0011). Everything a user relies on to *check* a
verdict — the protocol, the signatures, the merge — is open here.

## Components

| Path | What |
|---|---|
| `spec/` | Provider protocol v1 ([PROTOCOL](spec/PROTOCOL.md)): in-toto statement, feed, registry, api/v1 + store schemas; `opc_spec` |
| `schemas/` | The optional report extension (`predicate.report`): report, findings, AI passes (JSON Schema 2020-12) |
| `aggregator/` | `opc-aggregate`: verify feeds (Sigstore), merge verdicts, publish `api/v1/` + signed `store.json` |
| `collector/` | `opc-collect`: marketplace sync, GitHub activity, engagement, [ranking](docs/RANKING.md) |
| `site/` | Website (Astro, static): index, per-plugin reports, providers, static API under `api/v1/` ([README](site/README.md)) |
| `store/` | Native app store: standalone Quickshell app over one signed snapshot ([README](store/README.md)) |
| `plugin/` | `omarchy-plugin-check`: CLI, menu, QML panel and bar widget, install gate ([README](plugin/README.md)) |
| `standards/` | Shared lint/type/hook configs and tool pins |
| `docs/` | [ARCHITECTURE](docs/ARCHITECTURE.md) · [VERDICT-LOGIC](docs/VERDICT-LOGIC.md) · [THREAT-MODEL](docs/THREAT-MODEL.md) · [REPORT-DIMENSIONS](docs/REPORT-DIMENSIONS.md) · [RANKING](docs/RANKING.md) · [ENGINEERING](docs/ENGINEERING.md) · [decisions](docs/decisions/README.md) |

## Develop

`just setup` once, then `just check` before every commit. Everything else: [docs/ENGINEERING.md](docs/ENGINEERING.md).
AI agents: [CLAUDE.md](CLAUDE.md).

## Phase status

| Phase | Scope | Status |
|---|---|---|
| P3 | Provider protocol, aggregator, collector, signed snapshot | done locally; data repo + Pages next |
| P4 | Astro static site | built; Pages deploy pending a published snapshot |
| P5 | `omarchy-plugin-check` plugin (CLI, menu, QML panel, install gate), store app | done; mirror repo pending |
| P6 | Scheduling | planned |
| P7 | Scale to all plugins, search, activity tracking, dynamic detonation | future |

## Security

Report vulnerabilities privately through
[GitHub private vulnerability reporting](https://github.com/PrometheusRoot/omarchy-plugin-check/security/advisories/new)
only; scope and expectations are in [SECURITY.md](SECURITY.md).

## License

The code is [MIT](LICENSE) (every package's metadata says `MIT`). The data the aggregator and the
data repository publish (`api/v1/`, the signed snapshot and store bundle, `providers.json`, our
provider feed) is [CC BY 4.0](LICENSE-DATA): reuse it freely with attribution. Marketplace metadata
quoted in it and other providers' attestations stay under their owners' terms.
