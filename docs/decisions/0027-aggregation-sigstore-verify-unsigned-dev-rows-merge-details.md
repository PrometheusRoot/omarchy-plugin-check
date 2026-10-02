# 0027. Aggregation: Sigstore verification port, unsigned dev rows, merge details

- Status: accepted
- Date: 2026-10-02
- Supersedes: — (refines 0008, 0009)

## Context

ADR-0008/0009 fix the protocol and worst-of merging but leave open: how verification is wired and
tested offline, what signing time means for validity windows, how a dev deployment runs before any
provider signs, and corner cases of the merge (only untrusted rows, disagreeing providers, several
reviews per provider). Research (2026-10-02): sigstore-python 4.5 verifies DSSE bundles, but its
`Statement` model rejects `gitCommit` digests, so it cannot sign our statements;
`cosign attest-blob --statement` can.

## Decision

**Verification sits behind a `Verifier` port: `SigstoreVerifier` (sigstore-python, exact SAN +
issuer + GitHub workflow repository, signing time = Fulcio certificate notBefore) and
`UnsignedDevVerifier`, which is used only for `signing: none` providers in a registry with
`dev: true` and marks rows `unsigned-dev`; each provider contributes its latest row per plugin;
without a core/verified row the combined verdict is never `safe` (reported `unknown`); `contested`
= trusted rows two or more levels apart, or a trusted `safe` against a capped `risky`/`blocked`.**

## Consequences

- Real-bundle tests run offline against a recorded public-good bundle (GitHub CLI v2.102.0 build
  provenance; `aggregator/tests/data/sigstore/`) with the trust root bundled in sigstore-python:
  exact identity accepted; other SAN, issuer, repository or a tampered payload rejected.
- Providers sign with `cosign attest-blob --statement` in GitHub Actions (spec/PROTOCOL.md §2).
- A dev snapshot is labelled `dev: true` and its rows `unsigned-dev`; a non-dev registry with an
  unsigned provider yields no rows for it, and an unsigned non-dev registry is refused.
- Rows for unlisted, retired or built-in plugins, wrong repositories (after migrations), conflicts
  of interest, bad digests and out-of-window signatures are rejected and listed in
  `api/v1/meta.json` `rejected[]`. Merge invariants are property tests (`aggregator/tests/test_merge.py`).
- Combined verdicts may rest on different commits per provider (`combined.commits`); comparing the
  installed HEAD with the subject is the client's job (ADR-0013).
