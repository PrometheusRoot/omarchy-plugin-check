# 0039. The production key lives in the data repo, which signs the feed keyless and publishes the snapshot to its Pages

- Status: accepted
- Date: 2026-10-03
- Supersedes: — (completes 0013, 0028, 0033: the production key and where clients fetch from)

## Context

Clients need one place to fetch a production-signed snapshot, file by file: the CLI reads
`store-manifest.json`, then each listed file, then `api/v1/plugins/<id>.json` lazily (ADR-0032/0033).
Release assets are flat (no `api/v1/plugins/` tree, ≤ 1000 per release), so they cannot serve that.
`actions/attest` builds its own statement with sha256 subjects only, so it cannot sign our
`gitCommit` statements; `cosign attest-blob --statement` can (ADR-0027).

## Decision

**`PrometheusRoot/omarchy-plugin-check-data` holds our provider feed and publishes the snapshot:
`sign.yml` (push to master by the owner, dispatch, weekly; never a pull-request event) checks the
committed unsigned statements with `opc-feed check`, signs them and the rebuilt index keyless with
cosign (identity `…/sign.yml@refs/heads/master`) and commits only the bundles and the index;
`publish.yml` (daily + dispatch) runs this repository's collector and aggregator at a pinned
commit, signs `providers.json`, `store.json` and `store-manifest.json` with the production ed25519
key from the `OPC_SNAPSHOT_KEY` secret in jobs that run nothing but `ssh-keygen`, and deploys to the
data repo's GitHub Pages (the default `update` URL) plus an immutable release `snapshot-<version>`
with `snapshot.tar.gz`, which the site builds from.**

## Consequences

- The production public key is committed in `spec/keys/allowed_signers` (snapshot + providers
  namespaces) and `plugin/keys/allowed_signers` (snapshot only); the private half exists only as
  the secret and the maintainer's offline backup. Rotation: ship the new key next to the old one
  in a client release, switch the secret, drop the old line in the following release.
- Pages is mutable and that is fine: trust comes from the signature, expiry and anti-rollback,
  not from the host. The immutable releases keep every published snapshot for audit.
- The secret never reaches the job that parses marketplace data, READMEs or provider feeds or
  installs Python packages; that job only verifies the registry with the public key.
- Feed URL `https://raw.githubusercontent.com/PrometheusRoot/omarchy-plugin-check-data/master`:
  the signed feed is served straight from git, available as soon as `sign.yml` pushes.
- A statement is immutable once signed (`opc-feed check` fails if its bundle carries another);
  the index is always rebuilt from the statements, so a pushed `index.json` is never signed as is.
- Until the scanner's runner has a write token for the data repo, new reviews are committed by
  hand; the weekly re-index keeps the feed from expiring meanwhile.
