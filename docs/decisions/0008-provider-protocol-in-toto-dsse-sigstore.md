# 0008. Provider protocol: in-toto + DSSE + Sigstore

- Status: accepted
- Date: 2026-10-01
- Supersedes: —

## Context

Clients must verify who produced a verdict without trusting a mirror or our server.

## Decision

**Reports are in-toto Statement v1 envelopes (DSSE) in Sigstore bundles, signed keyless in the provider's CI; providers are listed in a signed, versioned, expiring `providers.json` with identity, tier and validity windows.**

## Consequences

- Subject = git repo + {gitCommit, gitTree}; predicateType on our domain.
- Feeds carry a monotonic version and an expiry; rollback/expired feeds are rejected.
- Our rich report is an optional predicate extension.
