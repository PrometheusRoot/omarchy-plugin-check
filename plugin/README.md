# Plugin Check for Omarchy

Commit-bound safety verdicts for Omarchy plugins, checked on your machine against one signed
snapshot of independent reviews. Not affiliated with Omarchy.

Omarchy plugins run unsandboxed inside `omarchy-shell`, and `omarchy plugin add` clones whatever
upstream HEAD is today. A review only means something for the commit it reviewed, so this
plugin compares what you install (or have installed) with what was reviewed, commit and tree.

- **`omarchy-plugin-check <git-url|id>`**: verdict card (combined + per-provider verdicts,
  criteria, reviewed commit vs upstream HEAD, your checkout, snapshot badge, marketplace link).
- **`omarchy-plugin-check --add [--enable] [--pin] [--force] [--yes] <git-url|id>`**: a gate in
  front of `omarchy plugin add`. Blocked or retired: refused (exit 2; `--force` is not honoured
  for them). Risky, caution, unreviewed, stale or unlisted: asks first (`--yes` for scripts).
  Safe: proceeds. `--pin` checks out the reviewed commit and verifies HEAD and its tree against
  the attested subject, or rolls the add back. Logs to `~/.config/omarchy/CHANGES.md` if you
  keep one.
- **`omarchy-plugin-check status [--json]`**: every plugin in `~/.config/omarchy/plugins` with
  its state: safe, caution, risky, blocked, unreviewed, stale, unlisted or retired, and a
  `pin` hint when a reviewed update (or a roll back) is available. Writes
  `~/.cache/omarchy-plugin-check/status.json` for the panel. Never uses the network.
- **`omarchy-plugin-check pin [--yes] <id>`**: move an installed plugin to the snapshot's reviewed
  commit: forward when a newer commit was reviewed, back when your HEAD is past the review. Shows
  the direction, the files changed and the verdict change, asks (`--yes` for scripts), checks out
  detached, verifies commit and tree against the signed snapshot, validates, rescans
  `omarchy-shell` and logs to CHANGES.md. Fetches from the listed repository, never a former
  `origin`. Refuses blocked (2), retired (2), unlisted (3) and unreviewed plugins. If only
  upstream moved, it says the plugin is stale and changes nothing. Use it instead of
  `omarchy plugin update` for pinned plugins: that one fast-forwards even a detached HEAD to
  unreviewed upstream HEAD (ADR-0035).
- **`omarchy-plugin-check update [<url|path>]`**: fetch and verify the signed client bundle
  (`store-manifest.json` + `.sig`, then sha256 and size of every file it lists, `store.json`
  included) or a bare signed `store.json`; expired or rolled-back snapshots are refused and the
  last accepted one is kept. Installs into `~/.cache/omarchy-plugin-check/`, where the store app
  reads it too. Source: the argument (manifest, `store.json` or their directory; https, a path or
  `file://`), `$OPC_SNAPSHOT_URL`, or the project's published URL.
- **`omarchy-plugin-check setup [--uninstall]`**: links the CLI into `~/.local/bin` and adds
  *Setup › Plugins › Check Plugin* and *Audit Plugins* to
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (a marked block; a backup is kept; your
  entries are never touched).
- **Bar widget + panel**: a shield tinted by the worst state (count of plugins in it); click for
  the list with each plugin's state, commit/tree match and reviewed outcome; rescan runs
  `status --json` once. Nothing polls.

Exit codes: 0 ok · 1 error or declined · 2 refused · 3 unlisted · 4 no verified snapshot.

## Install

```sh
omarchy plugin add https://github.com/PrometheusRoot/omarchy-plugin-check-plugin --enable
~/.config/omarchy/plugins/io.github.prometheusroot.plugin-check/bin/omarchy-plugin-check setup
omarchy-plugin-check update
```

`update` fetches the production snapshot from
`https://prometheusroot.github.io/omarchy-plugin-check-data/` (published daily, valid 7 days) and
verifies it with the production key in `keys/allowed_signers` (ADR-0039). Development snapshots
verify only with `OPC_DEV_KEYS=1 OPC_DEV_SIGNERS=<path to allowed_signers.dev>`.

## States

| State | Meaning |
|---|---|
| safe / caution / risky | trusted reviewers' combined verdict for the commit (or tree) you run |
| blocked | a trusted reviewer found blocking evidence; `--add` refuses it |
| unreviewed | no trusted review (only the unsigned marketplace baseline, or nothing) |
| stale | your commit and tree differ from the reviewed ones |
| unlisted | not on plugins.omarchy.org, or your checkout's origin is neither the listed repository nor one of its former names |

A checkout whose `origin` is a former name of the listed repository (a rename the marketplace
records in `repositoryMigrations`) keeps that listing and is marked *moved*. Commit and tree are
compared with the signed `verdict.commit` / `verdict.tree` of the snapshot (ADR-0034).
| retired | removed from the marketplace; no verdict is computed |

## Environment

`OPC_SNAPSHOT_URL` snapshot source · `OPC_OFFLINE=1` no `git ls-remote`, no report fetch ·
`OPC_GLYPHS=unicode` stand-ins for Nerd Font glyphs · `OPC_COLOR=always|never` · `NO_COLOR` ·
`OPC_DEV_KEYS=1` + `OPC_DEV_SIGNERS` development snapshots.

## Development

`lib/*.jq` hold every decision (pure jq, `include "opc"`), `bin/omarchy-plugin-check` is glue,
`lib/panel.mjs` is the panel's logic (pure ES module). Tests: `bats tests/` (temp HOME, fake
`omarchy`, fake `git ls-remote`, a snapshot signed with a key generated per test) and
`node --test 'lib/*.test.mjs'`. Lint: `tools/lint.sh` (shellcheck with every optional check, shfmt,
qmllint, qmlformat, `omarchy plugin validate`).
