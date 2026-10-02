# Provider protocol v1

How a security **provider** publishes verdicts about Omarchy plugins, and how a **consumer**
(the aggregator, the CLI, the store app) decides what to believe. Public; it is the only contract
between the open tool and any scanner, ours included (ADR-0007, ADR-0008, ADR-0026).

Schemas: [`schemas/`](schemas/) (JSON Schema 2020-12). Python helpers: `opc_spec` (vocabulary,
identifiers, validation). Example feed: [`examples/provider-feed/`](examples/provider-feed/).

## 1. The attestation

One review = one [in-toto Statement v1](https://github.com/in-toto/attestation/blob/main/spec/v1/statement.md)
([statement.schema.json](schemas/statement.schema.json)):

| Field | Value |
|---|---|
| `_type` | `https://in-toto.io/Statement/v1` |
| `subject[0].name` | `git+https://github.com/<owner>/<repo>` (the repository, as listed by the marketplace) |
| `subject[0].digest` | `{"gitCommit": "<40 hex>", "gitTree": "<40 hex>"}`; `gitTree` is optional but lets a client match a re-signed or rebased commit with identical content |
| `predicateType` | `https://prometheusroot.github.io/omarchy-plugin-check/attestation/security-review/v1` (base URL configurable per deployment; consumers compare exactly) |
| `predicate` | [predicate.schema.json](schemas/predicate.schema.json) |

Predicate: `provider{id, scannerVersion, method[]}`, `plugin{id, catalogGeneratedAt, target}`,
`timeReviewed`, `verdict` (`safe | caution | risky | blocked | unknown`),
`criteria{checked, failed, notChecked}` (vocabulary: `safe-to-run no-network no-exec
no-persistence no-privilege no-obfuscation no-secrets reviewed-by-human`), `scope{kind full|delta,
path, baseCommit}`, `findings[]{category, severity, confidence, message, blocking, locations[path,
startLine, endLine]}`, optional `quality{score}`, `policy{uri, digest}`, and the optional
`report` extension ([schemas/report.schema.json](../schemas/report.schema.json)).

**Coarse by design.** Findings carry a category, a severity and file:line evidence, never a rule
identifier, rule weight or score formula (`additionalProperties: false` rejects them). A provider
that embeds `report` must make rule identifiers opaque first (ADR-0011).

## 2. Signing

The statement is the payload of a [DSSE](https://github.com/secure-systems-lab/dsse/blob/master/envelope.md)
envelope (`payloadType: application/vnd.in-toto+json`), inside a
[Sigstore bundle](https://docs.sigstore.dev/about/bundle/) (`application/vnd.dev.sigstore.bundle.v0.3+json`),
signed **keyless** in the provider's GitHub Actions workflow (Fulcio certificate for the workflow
identity, Rekor transparency-log entry, `permissions: id-token: write`):

```sh
cosign attest-blob --statement statement.json --bundle "$commit.sigstore.json" --yes   # cosign >= 3
```

`--statement` signs the statement as built, so the subject stays the git commit (`--predicate`
would derive a sha256 subject from a file). sigstore-python verifies these bundles
(`Verifier.verify_dsse`), but its `Statement`/`StatementBuilder` reject `gitCommit` digests (it
only admits SHA-2/SHA-3 digest names), so it cannot sign them as of 4.5.

## 3. The feed

```
<feedUrl>/feed/v1/index.json                    feed-index.schema.json
<feedUrl>/feed/v1/index.json.sigstore.json      bundle over the exact bytes of index.json (message signature)
<feedUrl>/feed/v1/statements/<pluginId>/<commit>.sigstore.json
```

`index.json` lists every published attestation with its `sha256`, so the signed index commits to
every file. `version` strictly increases per publish; `expires` is at most 30 days after
`generatedAt`. Attestations never expire (a rule change means a rescan, not a re-signature).
The index signature is produced with `cosign sign-blob --bundle index.json.sigstore.json index.json`
or `sigstore sign --bundle`.

## 4. The registry

[`providers.json`](schemas/providers.schema.json): `id, name, kind (feed | marketplace-baseline),
tier (core | verified | community | unsigned), feedUrl, signing (sigstore | none),
sigstore{oidcIssuer, certificateIdentity (exact workflow SAN), repository}, validFrom,
validUntil, excludedWindows[], criteriaSupported[], conflictsOfInterest[], contact`. The registry
itself is versioned, expiring and signed with the project key (`ssh-keygen -Y sign -n
omarchy-plugin-check-providers`). `signing: none` is accepted only in a registry with `dev: true`.

## 5. What a consumer does

1. Verify the registry signature; reject it if expired or older than the last accepted version.
2. Per feed provider: fetch `index.json` + bundle; verify the bundle against the registry identity
   (issuer + exact SAN); reject the feed if `provider`/`predicateType` differ from the registry,
   it is expired, or its `version` is lower than the last accepted one (rollback).
3. Per entry: fetch the file, check `sha256`, verify the bundle against the same identity, check the
   signing time (Rekor integrated time) is inside `validFrom..validUntil` and outside every
   `excludedWindows`, validate the statement, and require that the subject repository is the
   marketplace repository of `predicate.plugin.id` (after `repositoryMigrations`). Retired or
   unlisted plugins and conflicts of interest are ignored.
4. Merge (ADR-0009, pure and identical in aggregator, CLI and store):
   - per provider, the latest row per plugin (by `timeReviewed`);
   - `blocked` without a `blocking` finding with a file:line location → `risky`;
   - tiers `community` and `unsigned` (the marketplace baseline) are capped at `caution`;
   - **combined = worst-of** the effective verdicts; `unknown` never wins;
   - if no `core`/`verified` row decided it, the combined verdict cannot be `safe` (it is `unknown`);
   - `contested` when trusted rows differ by two or more levels, or a trusted `safe` meets a capped
     `risky`/`blocked`.

The marketplace baseline (registry.json `automatedSecurityBaseline.outcome`) maps
`passed → safe`, `review-required → caution`, `needs-fixes → risky`, and is always tier `unsigned`.

## 6. The snapshot

The aggregator publishes one compact [`store.json`](schemas/store.schema.json) (marketplace
metadata, GitHub activity, ranking, shelves, per-provider verdicts and the combined verdict; per
plugin also the deciding trusted row's `verdict.criteria` and `verdict.risk`, the marketplace
`ini`/`accent`, the reviewed `verdict.commit` with its `verdict.tree`, and `formerRepos`) with a
detached SSH signature (`store.json.sig`, namespace
`omarchy-plugin-check-snapshot`, ed25519). It is the CLI's contract. Clients verify it offline
before use (ADR-0013):

```sh
spec/verify-snapshot.sh store.json store.json.sig spec/keys/allowed_signers
```

which runs `ssh-keygen -Y verify -f allowed_signers -I omarchy-plugin-check -n
omarchy-plugin-check-snapshot -s store.json.sig < store.json` and then rejects an expired snapshot
or a `version` lower than the last accepted one. `spec/keys/dev-snapshot.pub` is a **development
key only**; snapshots signed with it carry `"dev": true`.

Identity fields a client binds an installed checkout with (ADR-0034):

| Field | Present when | Meaning |
|---|---|---|
| `verdict.commit` | trusted basis, every decided row at one commit | the reviewed commit |
| `verdict.tree` | with `commit`, when the trusted rows of that commit name one `subject.digest.gitTree` | its tree: `HEAD^{tree}` equal to it is the reviewed content (re-signed or rebased commit) |
| `formerRepos[]` | the registry has `repositoryMigrations` / `repositoryIdentity.previousRepositories` for the listing | previous repository URLs (lower-cased); a checkout whose `origin` is one of them is this listing, moved. A name that is another listing's current repository is never included |

## 7. The store client bundle

Next to `store.json` the same build writes the store app's bundle (ADR-0032), a projection of
`store.json` shaped for a fast cold start:

| File | Schema | Content |
|---|---|---|
| `store-manifest.json` (+ `.sig`) | [store-manifest](schemas/store-manifest.schema.json) | `version`, `expires`, `dev` (as store.json) and `{role, path, sha256, size}` of every file below and of `store.json` |
| `store-home.json` | [store-home](schemas/store-home.schema.json) | envelope, counts, shelves (12 ids each) and only the rows they reference |
| `store-search.json` | [store-search](schemas/store-search.schema.json) | every plugin as parallel arrays; repeated strings interned in `dict` |
| `store-details.json` | [store-details](schemas/store-details.schema.json) | plugin id → sha256 of `apiBase` + `plugins/<id>.json` |

Only the manifest is signed: `ssh-keygen -Y sign -n omarchy-plugin-check-snapshot` (the snapshot
namespace; its `kind` keeps it apart from store.json). A client verifies the manifest signature,
`kind`, expiry and rollback **before parsing anything else**, then each file's size and sha256;
a detail document is used only if its sha256 is the one `store-details.json` lists. The store
app's verifier is `store/bin/omarchy-plugin-store-verify` (bash + ssh-keygen + jq + sha256sum):

```sh
OPC_STORE_DEV_KEYS=1 store/bin/omarchy-plugin-store-verify bundle DIR      # DEV key only when asked
store/bin/omarchy-plugin-store-verify detail DIR <plugin id>                # prints the verified doc
```

In a snapshot build every plugin has a detail document (`api/v1/plugins/<id>.json`) carrying
its full store row (`listing`, including the README `gallery`), weekly commits
(`activity.weeks`) and each feed row's `detail.report` when the provider embedded the optional
`report` extension (`opsec attest|feed --include-report`: capabilities, system areas, network
hosts, dependencies + advisories, performance, code quality, maintenance, AI summary, verdict
reasons and criteria; rule identifiers already opaque).
