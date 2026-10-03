# Runbook

How to build and verify a snapshot of the public pipeline. Operating our provider (the private
scanner and its batch runner) is documented in the private repository.

## Store snapshot (local dev)

Public pipeline (ADR-0026..0029): marketplace sync → GitHub stats → aggregate → rank → signed
`store.json`. Needs `gh auth login` (read-only use of its token) and, once, the DEV key:

```
opc-aggregate keygen                                   # ~/.config/omarchy-plugin-check/dev-snapshot-key (600)
# W/opc-feed: a provider feed (spec/PROTOCOL.md §feed); ours is produced by the private scanner,
# any provider's unsigned dev feed works for a dev registry
opc-aggregate sign registry W/providers.dev.json       # dev registry: opc (core, signing none) + marketplace
just snapshot --out W --providers W/providers.dev.json --providers-sig W/providers.dev.json.sig \
    [--seed-catalog old-catalog.json]                  # writes W/api/v1, W/store.json(.sig) and the store
                                                       # client bundle (store-manifest.json(.sig) + home/search/
                                                       # details, ADR-0032), verifies both
spec/verify-snapshot.sh W/store.json                   # what the CLI runs
OPC_STORE_DEV_KEYS=1 store/bin/omarchy-plugin-store-verify bundle W   # what the store app runs
opc-collect github --repo owner/name                   # refresh chosen repos now (e.g. weekly activity)
store/tools/dev-bundle.sh W                            # refresh the store's bundled dev data from W
```

The GitHub step took 40 min for the full catalog on the first run (2026-10-02: 4,726 repos,
390 queries of 12, 1,169 of 5,000 points, no 502 at batch 12); it caches per repository under
`~/.cache/omarchy-plugin-check/collector/github/` and exits 3 when it stopped early (rate limit):
rerun the same command to resume. A dev snapshot says `"dev": true` and is signed with the DEV key;
never publish it.
