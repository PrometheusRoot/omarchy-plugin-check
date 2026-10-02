# 0033. The checker plugin gates `omarchy plugin add` in bash over pure jq filters, and binds identity to the listed repository

- Status: accepted
- Date: 2026-10-02
- Supersedes: — (implements 0013, 0028 and the CLI side of 0032 on the client)

## Context

The checker runs on every Omarchy machine, so it may only use what Omarchy ships (bash, jq,
git, ssh-keygen, curl, gum, Quickshell). `store.json` signs one reviewed commit per plugin but
no tree; the per-plugin detail documents (findings, tree) are covered only through the client
bundle's signed manifest (ADR-0032). A fork can reuse a listed plugin id, and `omarchy plugin
add` clones mutable upstream HEAD.

## Decision

**`bin/omarchy-plugin-check` is bash glue over pure jq filters (`plugin/lib/*.jq`); `update`
installs the signed client bundle (manifest signature, kind, expiry, rollback shared with the
store's `store-bundle-version`, sha256 + size of every listed file) or a bare signed `store.json`;
every command re-verifies before parsing, and it matches an installed plugin to a listing only when
its id and its `origin` repository both match; `--add` refuses blocked and retired plugins
(exit 2, `--force` never overrides), asks for everything that is not safe at the reviewed
commit, and with `--pin` checks out the signed commit and requires HEAD and `HEAD^{tree}` to
equal the attested subject or rolls the add back.**

## Consequences

- No new runtime dependency; every decision (identity, state, gate, card, menu and CHANGES.md
  edits) is a jq filter tested by bats with a fake `omarchy`, fake `git ls-remote` and a
  snapshot signed by a key generated in the test. `--force` only allows an unreviewed add when
  no snapshot verifies, never with `--pin`.
- Trust: `keys/allowed_signers` ships the production key (none published yet, so nothing
  verifies); the dev key is accepted only with `OPC_DEV_KEYS=1` from a separate file
  (`OPC_DEV_SIGNERS`), never shipped (ADR-0028). Metadata and the lookup index are cached by
  the snapshot's sha256, so a check costs one `ssh-keygen -Y verify`.
- A detail document is used only if its sha256 is the one the signed `store-details.json` lists
  (without a bundle it is display-only); the tree is taken from a counted core/verified row of the
  signed commit, so a commit match never depends on it. Follow-up for the spec: carry
  `verdict.tree` and previous repository names (renames) in `store.json`.
- Privacy (ADR-0013): `status` never touches the network; `check` makes one `git ls-remote` and
  fetches one per-plugin view (cached; `OPC_OFFLINE=1` skips both).
- `--pin` leaves a detached HEAD, so `omarchy plugin update` will not move it (logged in
  CHANGES.md); re-pinning on update is future work.
- Exit codes: 0 ok, 1 error or declined, 2 refused, 3 unlisted, 4 no verified snapshot.
