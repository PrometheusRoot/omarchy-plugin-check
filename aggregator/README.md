# opc-aggregator (aggregator/)

Public. Reads the provider registry, verifies every provider feed, merges verdicts and publishes the
static API (`api/v1/`) and the signed store snapshot (`store.json` + `store.json.sig`).
Protocol: [spec/PROTOCOL.md](../spec/PROTOCOL.md). Decisions: ADR-0008, 0009, 0013, 0026, 0027.

```
opc-aggregate build --providers providers.json [--providers-sig providers.json.sig] \
    --catalog catalog.json --registry registry.json --out OUT \
    [--stats stats.json --ranking ranking.json --sign-key KEY]     # + store.json
opc-aggregate keygen                 # DEV key → ~/.config/omarchy-plugin-check/dev-snapshot-key
opc-aggregate sign registry|snapshot FILE [--key KEY]
opc-aggregate verify-snapshot store.json [--allowed-signers F] [--min-version N]
```

| Module | Role |
|---|---|
| `model` / `ports` | value types; `Fetcher` + `Verifier` ports |
| `marketplace` | catalog + registry identity, migrations, the unsigned baseline rows (pure) |
| `admit` / `merge` | admission (expiry, rollback, windows, identity) and merge rules (pure, property-tested) |
| `statements` / `api` / `snapshot` | statement → row; api/v1 documents; store.json (pure) |
| `fetch` / `sigstore_verifier` / `unsigned` / `sshsig` / `state` | adapters: HTTPS/local, sigstore-python (the only `sigstore` import), dev unsigned, `ssh-keygen -Y`, anti-rollback state |
| `build` / `publish` | the run; writing files (schema-validated) |
| `cli` | composition root |
