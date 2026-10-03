# 0042. omarchy-store: one repository, one command; the bar opens the store

- Status: accepted
- Date: 2026-10-03
- Supersedes: part of 0014 (how the store is installed and launched) and of 0033 (the mirror holds `plugin/` only; the bar click opens the panel)

## Context

Installing took four steps (add the checker plugin, run `setup`, run `update`, find the store,
which was not shipped at all). `omarchy plugin add` clones a whole repository and only loads the
manifest's entry points, refuses symlinks, and runs nothing at install time, so anything beyond
"clone + enable" has to start from the user's first click. Changing keybinds, the menu or
`~/.local/bin` without asking is not acceptable.

## Decision

**`PrometheusRoot/omarchy-store` (the renamed plugin mirror) is built by `scripts/build-mirror.sh`
from this repository: the checker plugin at its root (id `io.github.prometheusroot.omarchy-store`)
and the store app in `store/`, without tests or dev data; `omarchy plugin add
https://github.com/PrometheusRoot/omarchy-store --enable` is the whole install; a left click on
the bar shield runs `store/bin/omarchy-store` by absolute path (single instance), right click
toggles the verdict panel; on first run the store runs the bundled checker's `update` itself;
the menu entry, keybind and `~/.local/bin` links are an opt-in from the store's status tab that
lists every change from `omarchy-plugin-check setup --plan --json` before applying it.**

## Consequences

- One tree, one history: the mirror gets one generated commit per release on top of its previous
  history (`release: omarchy-store X.Y.Z`, dated like the source commit), tagged `vX.Y.Z` by
  `.github/workflows/mirror.yml` on a tag here; it needs the `MIRROR_DEPLOY_KEY` secret (an
  ed25519 deploy key with write access to the mirror). Omarchy's own `omarchy-plugin-validate`
  (pinned by commit and sha256 when Omarchy is not installed) must pass before anything is pushed.
- No PATH dependency: the bar, the panel and the store run the checker as `<plugin>/bin/omarchy-plugin-check`
  (the store probes `../bin` then `../plugin/bin` next to itself); the verifier finds `keys/` the
  same way. The CLI keeps its name and its state under `~/.cache/omarchy-plugin-check`,
  `~/.local/state/omarchy-plugin-check`: the store and the CLI share one verified snapshot.
- First run is a pure state machine (`store/lib/firstrun.mjs`): verify → (missing, expired or
  damaged) update once → verify; failures show a title, one line and *retry*.
- `setup` plans from one set of facts (`plugin/lib/setup.jq`); the keybind is the first free of
  Super+Shift+S, Super+Shift+Alt+S, Super+Ctrl+Shift+S, Super+Ctrl+Alt+S by a read-only
  `hyprctl -j binds` (`plugin/lib/keybind.jq`), written as a marked block in
  `~/.config/hypr/bindings.lua` (or `bindings.conf`); every edited file is backed up; `setup
  --uninstall` (the store's *undo*) removes only our links and blocks. Without a terminal `setup`
  needs `--yes`.
- Tests: `plugin/tests/setup.bats` (plan, apply, idempotence, undo, conflicts, conf format),
  `store/tests/launcher.bats` (single instance, link, `--dev`, no Hyprland), node tests of
  `firstrun`, `extras`, `install` (checker path) and `panel` (store argv).
