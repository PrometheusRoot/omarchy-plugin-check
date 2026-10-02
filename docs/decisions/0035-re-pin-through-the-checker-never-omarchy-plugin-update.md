# 0035. Re-pin through `omarchy-plugin-check pin`, never `omarchy plugin update`

- Status: accepted
- Date: 2026-10-02
- Supersedes: part of 0033 ("`--pin` leaves a detached HEAD, so `omarchy plugin update` will not move it")

## Context

`omarchy plugin update [id]` runs `git fetch origin HEAD` and `git merge --ff-only FETCH_HEAD`,
then validates and rescans. Tested 2026-10-02 (git 2.55): `merge --ff-only` fast-forwards a
detached HEAD too, so it moves a pinned plugin to unreviewed upstream HEAD, from whatever
`origin` says (for a renamed repository, the old name), without any verdict. ADR-0033 claimed the
opposite. A pinned plugin still needs a way to follow its reviews.

## Decision

**`omarchy-plugin-check pin [--yes] <id>` is the update path for pinned plugins: it identifies
the checkout like `status` (id + origin, former names allowed), refuses blocked, retired,
unlisted and unreviewed plugins, fetches from the listed repository (not `origin`), and moves to
the snapshot's reviewed commit only when HEAD is not it already (forward = update, back = HEAD is
past the review), after showing direction, files changed (`git diff --name-status`, no external
diff drivers or textconv) and the verdict change (from `pins.json`); it confirms (or `--yes`),
checks out detached, requires HEAD and `HEAD^{tree}` to equal the signed `verdict.commit` /
`verdict.tree`, validates, rescans `omarchy-shell` and logs to CHANGES.md; when only upstream
moved it says the plugin is stale and changes nothing.**

## Consequences

- The store's installed tab offers *update* / *roll back* from `status --json` (`repin`:
  forward / back, from `git merge-base` on local objects; a reviewed commit not yet fetched counts
  as forward) and runs `omarchy-plugin-check pin --yes <id>` as argv after its own confirm.
- `omarchy plugin update` stays Omarchy's tool; we do not wrap or block it. If someone runs it on
  a pinned plugin, `status` shows `stale` and `pin` rolls it back. README, CHANGES.md entries and
  the `--add --pin` prompt say so.
- `pin` needs the network (refused with `OPC_OFFLINE=1`); `status` stays offline.
- The pin record (`~/.local/state/omarchy-plugin-check/pins.json`: commit, verdict, snapshot
  version, time) is display data only; trust always comes from the signed snapshot.
- Tests: `plugin/tests/pin.bats` (forward, back, stale upstream, refusals, moved origin, tree
  mismatch, offline) against a fake `git fetch` and a fake `omarchy-shell`.
