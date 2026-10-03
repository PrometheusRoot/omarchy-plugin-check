# Keys

| File | What |
|---|---|
| `allowed_signers` | **Production** ed25519 key (ADR-0039), `SHA256:pjXUzN+57yC2zez/zQd1BGKfnY5eopJDJH1GJLop8vQ`, restricted to the snapshot and registry namespaces. Signs `store.json`, `store-manifest.json` and `providers.json` in the data repository's `publish.yml`; the private half exists only as that repository's `OPC_SNAPSHOT_KEY` Actions secret (and an offline backup). |
| `dev-snapshot.pub` | **DEV ONLY** ed25519 key for local snapshots and dev registries. Private half: `~/.config/omarchy-plugin-check/dev-snapshot-key` (mode 600, never in the repo; `opc-aggregate keygen`). |
| `allowed_signers.dev` | `ssh-keygen -Y verify` allowed_signers for the DEV key, restricted to the snapshot and registry namespaces. |

Clients ship `allowed_signers` (the checker plugin ships its own copy, snapshot namespace only:
`plugin/keys/allowed_signers`) and never `allowed_signers.dev`. Rotation: add the new key as a
second line and release the clients, switch the secret, then drop the old line (ADR-0039).
