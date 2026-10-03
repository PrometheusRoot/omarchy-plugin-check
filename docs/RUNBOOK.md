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

## Production snapshot (data repo, ADR-0039)

[`PrometheusRoot/omarchy-plugin-check-data`](https://github.com/PrometheusRoot/omarchy-plugin-check-data)
runs the same pipeline in GitHub Actions; nothing production-signed is built on a laptop.

| Workflow | When | Does |
|---|---|---|
| `sign.yml` | push to `feed/` on master by the owner, dispatch, weekly | `opc-feed check` → `cosign attest-blob --statement` per new statement → `opc-feed index` → `cosign sign-blob` the index → commit bundles + index → dispatch `publish.yml` |
| `publish.yml` | daily 04:17 UTC, dispatch | stamp + sign `providers.json` → collector (GITHUB_TOKEN, cache) + aggregator (Sigstore identities from the registry) at the pinned commit of this repo → sign `store.json` + `store-manifest.json` → verify with `spec/keys/allowed_signers` → Pages + immutable release `snapshot-<version>` |

Add reviews: commit the unsigned `feed/v1/statements/<id>/<commit>.json` from `opsec feed` to the
data repo's master (signed statements are immutable; the index is rebuilt by `sign.yml`).
Upgrade the tool: bump `OPC_TOOL_COMMIT` in both workflows (and `ci/requirements.lock` if a
dependency changed). Check a published snapshot from anywhere:

```
b=https://prometheusroot.github.io/omarchy-plugin-check-data
curl -fsSLO "$b/store.json" -fsSLO "$b/store.json.sig"
spec/verify-snapshot.sh store.json store.json.sig spec/keys/allowed_signers
```

The site (`site.yml`) builds daily from `vars.OPC_SNAPSHOT_URL` =
`https://github.com/PrometheusRoot/omarchy-plugin-check-data/releases/latest/download/snapshot.tar.gz`.
