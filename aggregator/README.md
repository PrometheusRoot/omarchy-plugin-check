# opc-aggregator (aggregator/)

Public. Reads the provider registry, verifies every provider feed, merges verdicts and publishes the
static API (`api/v1/`), the signed store snapshot (`store.json` + `store.json.sig`, the CLI's
contract) and the store app's client bundle (`store-manifest.json` + `.sig` over `store-home.json`,
`store-search.json`, `store-details.json`; ADR-0032). Protocol: [spec/PROTOCOL.md](../spec/PROTOCOL.md).
Decisions: ADR-0008, 0009, 0013, 0026, 0027, 0028, 0032.

```
opc-aggregate build --providers providers.json [--providers-sig providers.json.sig] \
    --catalog catalog.json --registry registry.json --out OUT \
    [--stats stats.json --ranking ranking.json --sign-key KEY]     # + store.json + client bundle
opc-aggregate client-bundle store.json --out DIR [--api api/v1] [--sign-key KEY]   # bundle from a store.json
opc-aggregate keygen                 # DEV key → ~/.config/omarchy-plugin-check/dev-snapshot-key
opc-aggregate sign registry|snapshot FILE [--key KEY]
opc-aggregate verify-snapshot store.json [--allowed-signers F] [--min-version N]
```

| Module | Role |
|---|---|
| `model` / `ports` | value types; `Fetcher` + `Verifier` ports |
| `marketplace` | catalog + registry identity, migrations, the unsigned baseline rows (pure) |
| `admit` / `merge` | admission (expiry, rollback, windows, identity) and merge rules (pure, property-tested) |
| `statements` / `api` / `snapshot` | statement → row (incl. the optional `report` extension); api/v1 documents (with `listing` + `activity` in a snapshot build); store.json (pure) |
| `client` | store.json → the store app's bundle: home slice, search columns, detail hashes, manifest (pure) |
| `fetch` / `sigstore_verifier` / `unsigned` / `sshsig` / `state` | adapters: HTTPS/local, sigstore-python (the only `sigstore` import), dev unsigned, `ssh-keygen -Y`, anti-rollback state |
| `build` / `publish` | the run; writing files (schema-validated), signing store.json and the manifest |
| `cli` | composition root |
