# Keys

| File | What |
|---|---|
| `dev-snapshot.pub` | **DEV ONLY** ed25519 key for local snapshots and dev registries. Private half: `~/.config/omarchy-plugin-check/dev-snapshot-key` (mode 600, never in the repo; `opc-aggregate keygen`). |
| `allowed_signers.dev` | `ssh-keygen -Y verify` allowed_signers for the DEV key, restricted to the snapshot and registry namespaces. |

The production key (ADR-0013) is not created yet; it will live in the publishing CI's secret store
and be added here as `allowed_signers`. Clients must never ship `allowed_signers.dev`.
