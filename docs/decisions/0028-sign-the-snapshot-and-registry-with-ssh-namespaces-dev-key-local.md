# 0028. Sign the snapshot and the registry with SSH signatures per namespace; dev key stays local

- Status: accepted
- Date: 2026-10-02
- Supersedes: — (implements 0013)

## Context

ADR-0013 picks `ssh-keygen -Y verify` so clients need no extra tooling. Still open: which data a
signature may be replayed onto, how clients detect stale or rolled-back files, and how to develop
before a production key exists without a key in the repository.

## Decision

**`store.json` and `providers.json` carry detached ed25519 SSH signatures with distinct namespaces
(`omarchy-plugin-check-snapshot`, `omarchy-plugin-check-providers`) and an `allowed_signers` entry
restricted to those namespaces; both documents carry a monotonic `version` (unix seconds) and an
`expires` (snapshot 7 days, registry ≤ its own field), and clients reject bad signatures, expired
files and versions below the last accepted one; development uses a local DEV key in
`~/.config/omarchy-plugin-check/dev-snapshot-key` (mode 600) whose public half is committed as
`spec/keys/dev-snapshot.pub` and whose snapshots say `dev: true`.**

## Consequences

- One verification path for every client: `spec/verify-snapshot.sh` (bash + ssh-keygen + jq) and
  `opc-aggregate verify-snapshot` behave the same; JSON is parsed only after the signature verifies.
- Aggregator state (`aggregator-state.json`) remembers the last registry, feed and snapshot
  versions, so a rollback is caught on the producer side too.
- The production key and its rotation are open (it will live in the publishing CI's secrets);
  `allowed_signers.dev` must never ship in a client.
