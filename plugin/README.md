# omarchy-store

An app store for Omarchy plugins, with commit-bound safety verdicts checked on your machine.
**Independent community project · not affiliated with Omarchy.**

```sh
omarchy plugin add https://github.com/PrometheusRoot/omarchy-store --enable
```

That is the whole install. Click the shield in your bar: the store opens, fetches the signed
snapshot of reviews, verifies it, and shows the catalog.

| | What you get |
|---|---|
| ▦ | **Store**: browse, search and install ~4,800 plugins, pinned to the reviewed commit |
| ⛨ | **Bar shield**: tinted by the worst state of what you run; right click for the verdict list |
| ✓ | **Verified locally**: one signed snapshot (`ssh-keygen -Y`) + sha256 of every file; blocked plugins are refused |
| ⌨ | **Optional**: menu entry, keybind and terminal commands, from the store's status tab, after you confirm the exact changes |

Omarchy plugins run unsandboxed inside `omarchy-shell`, and `omarchy plugin add` clones whatever
upstream HEAD is today. A review only means something for the commit it reviewed, so the store
compares what you install (or have installed) with what was reviewed, commit and tree.

Source, issues and the review protocol:
[PrometheusRoot/omarchy-plugin-check](https://github.com/PrometheusRoot/omarchy-plugin-check)
(this repository is built from it, ADR-0042).

## Using it

- **Bar shield**: left click opens the store (a second click focuses it), right click toggles the
  verdict panel (each installed plugin's state, commit/tree match and reviewed outcome; *store*
  and *rescan* buttons), middle click rescans. Nothing polls.
- **First run**: the store downloads the signed snapshot from
  `https://prometheusroot.github.io/omarchy-plugin-check-data/` (published daily, valid 7 days),
  verifies it with the key in `keys/allowed_signers` (ADR-0039) and shows *retry* if anything
  fails. An expired snapshot is refreshed the same way.
- **Extras** (store › status › *add menu + keybind + terminal command*, or `e`): links
  `omarchy-plugin-check` and `omarchy-store` into `~/.local/bin`, adds *Install › Plugin Store*
  and *Setup › Plugins › Check Plugin / Audit Plugins* to
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`, and binds the first free of
  Super+Shift+S, Super+Shift+Alt+S, Super+Ctrl+Shift+S, Super+Ctrl+Alt+S in
  `~/.config/hypr/bindings.lua` (asked read-only from `hyprctl binds`). The dialog lists each
  change first; edited files are backed up; *undo* removes only what was added.

## Checker CLI

`bin/omarchy-plugin-check` (on your PATH after the extras, else run it from the plugin folder):

- **`omarchy-plugin-check <git-url|id>`**: verdict card (combined + per-provider verdicts,
  criteria, reviewed commit vs upstream HEAD, your checkout, snapshot badge, marketplace link).
- **`omarchy-plugin-check --add [--enable] [--pin] [--force] [--yes] <git-url|id>`**: a gate in
  front of `omarchy plugin add`. Blocked or retired: refused (exit 2; `--force` is not honoured
  for them). Risky, caution, unreviewed, stale or unlisted: asks first (`--yes` for scripts).
  Safe: proceeds. `--pin` checks out the reviewed commit and verifies HEAD and its tree against
  the attested subject, or rolls the add back. Logs to `~/.config/omarchy/CHANGES.md` if you
  keep one. The store installs through this.
- **`omarchy-plugin-check status [--json]`**: every plugin in `~/.config/omarchy/plugins` with
  its state and a `pin` hint when a reviewed update (or a roll back) is available. Writes
  `~/.cache/omarchy-plugin-check/status.json` for the panel. Never uses the network.
- **`omarchy-plugin-check pin [--yes] <id>`**: move an installed plugin to the snapshot's reviewed
  commit: forward when a newer commit was reviewed, back when your HEAD is past the review. Shows
  the direction, the files changed and the verdict change, asks (`--yes` for scripts), checks out
  detached, verifies commit and tree against the signed snapshot, validates, rescans
  `omarchy-shell` and logs to CHANGES.md. Fetches from the listed repository, never a former
  `origin`. Refuses blocked (2), retired (2), unlisted (3) and unreviewed plugins. Use it instead
  of `omarchy plugin update` for pinned plugins: that one fast-forwards even a detached HEAD to
  unreviewed upstream HEAD (ADR-0035).
- **`omarchy-plugin-check update [<url|path>]`**: fetch and verify the signed client bundle
  (`store-manifest.json` + `.sig`, then sha256 and size of every file it lists) or a bare signed
  `store.json`; expired or rolled-back snapshots are refused and the last accepted one is kept.
  Installs into `~/.cache/omarchy-plugin-check/`, which the store reads too. Source: the argument,
  `$OPC_SNAPSHOT_URL`, or the published URL above.
- **`omarchy-plugin-check setup [--uninstall] [--plan] [--json] [--yes]`**: the extras above.
  `--plan` prints what would change and stops; without a terminal it needs `--yes`.

Exit codes: 0 ok · 1 error or declined · 2 refused · 3 unlisted · 4 no verified snapshot.

## States

| State | Meaning |
|---|---|
| safe / caution / risky | trusted reviewers' combined verdict for the commit (or tree) you run |
| blocked | a trusted reviewer found blocking evidence; `--add` refuses it |
| unreviewed | no trusted review (only the unsigned marketplace baseline, or nothing) |
| stale | your commit and tree differ from the reviewed ones |
| unlisted | not on plugins.omarchy.org, or your checkout's origin is neither the listed repository nor one of its former names |
| retired | removed from the marketplace; no verdict is computed |

A checkout whose `origin` is a former name of the listed repository (a rename the marketplace
records in `repositoryMigrations`) keeps that listing and is marked *moved*. Commit and tree are
compared with the signed `verdict.commit` / `verdict.tree` of the snapshot (ADR-0034).

## Environment

`OPC_SNAPSHOT_URL` snapshot source · `OPC_OFFLINE=1` no `git ls-remote`, no report fetch ·
`OPC_GLYPHS=unicode` stand-ins for Nerd Font glyphs · `OPC_COLOR=always|never` · `NO_COLOR` ·
`OPC_DEV_KEYS=1` + `OPC_DEV_SIGNERS` development snapshots (`OPC_DEV_SIGNERS` = path to an
`allowed_signers.dev`).

## Remove

`omarchy-plugin-check setup --uninstall --yes` (if you added the extras), then
`omarchy plugin remove io.github.prometheusroot.omarchy-store`. The snapshot cache stays in
`~/.cache/omarchy-plugin-check/`.

## Development

In [omarchy-plugin-check](https://github.com/PrometheusRoot/omarchy-plugin-check) `plugin/`:
`lib/*.jq` hold every decision (pure jq, `include "opc"`), `bin/omarchy-plugin-check` is glue,
`lib/panel.mjs` is the panel's logic (pure ES module). Tests: `bats tests/` (temp HOME, fake
`omarchy`, fake `git ls-remote` and `hyprctl`, a snapshot signed with a key generated per test)
and `node --test 'lib/*.test.mjs'`. Lint: `tools/lint.sh` (shellcheck with every optional check,
shfmt, qmllint, qmlformat, `omarchy plugin validate`). This repository's tree is produced by
`scripts/build-mirror.sh` there.
